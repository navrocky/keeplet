#!/usr/bin/env bash
# Publishes a .plasmoid on the KDE Store (store.kde.org = Pling/opendesktop): uploads it with its
# version, archives the older files, adds or updates the changelog entry for the version and sets
# the product's Version field.
# Run by .github/workflows/release.yml on a release tag; locally use only --dry-run (docs/release.md).
#
# Pling has no write API, so this drives the same AJAX endpoints as the product edit page, signed
# in with e-mail + password (KDE_STORE_USERNAME / KDE_STORE_PASSWORD). The endpoints are
# undocumented; if the store changes them, this fails and the file is uploaded by hand.
#
#   scripts/kde-store-upload.sh [--dry-run] <product-id> <file.plasmoid> [notes-file]
#
# --dry-run only signs in and reads the edit page. A missing notes file means no changelog entry.
set -euo pipefail

BASE_URL=https://www.opendesktop.org
# The site is behind a bot check (Anubis) that challenges browser user agents and blocks curl's.
USER_AGENT=keeplet-release-upload

dry_run=0
if [[ "${1:-}" == --dry-run ]]; then dry_run=1; shift; fi
product="${1:?usage: $0 [--dry-run] <product-id> <file.plasmoid> [notes-file]}"
file="${2:?usage: $0 [--dry-run] <product-id> <file.plasmoid> [notes-file]}"
notes="${3:-}"
: "${KDE_STORE_USERNAME:?KDE_STORE_USERNAME is not set}" "${KDE_STORE_PASSWORD:?KDE_STORE_PASSWORD is not set}"
[[ "$product" =~ ^[0-9]+$ ]] || { echo "bad product id: $product" >&2; exit 1; }
[[ -f "$file" ]] || { echo "no such file: $file" >&2; exit 1; }
for tool in curl jq unzip python3; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done

version="$(unzip -p "$file" metadata.json | jq -r '.KPlugin.Version // empty')"
[[ -n "$version" ]] || { echo "no KPlugin.Version in $file" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
jar="$work/cookies"
# The site shows an age-verification page instead of the content without this cookie.
printf '%s\tFALSE\t/\tFALSE\t0\tverified\t1\n' "${BASE_URL#https://}" > "$jar"

edit_url="$BASE_URL/p/$product/edit"

# Prints a page to stdout as one line (the HTML is matched with grep below).
get_page() {
    curl -sS --fail-with-body -A "$USER_AGENT" -L --retry 3 -b "$jar" -c "$jar" "$@" | tr '\n\r' '  '
}

# AJAX POST of the edit page; prints the JSON response.
post_ajax() {
    curl -sS --fail-with-body -A "$USER_AGENT" -L -b "$jar" -c "$jar" \
        -H 'X-Requested-With: XMLHttpRequest' -H 'Accept: application/json' -H "Referer: $edit_url" \
        "$@"
}

# Fails unless the JSON response's .status is the expected one. Never prints the body: it may hold
# session details.
check_status() { # <step> <expected> <json>
    local status
    status="$(jq -r '.status // empty' <<<"$3" 2>/dev/null || true)"
    [[ "$status" == "$2" ]] || { echo "$1 failed: status '${status:-<not JSON>}'" >&2; exit 1; }
}

# The value of an HTML attribute in a tag, empty if absent.
attr() { # <tag> <name>
    grep -oP "\\b$2=[\"']\\K[^\"']*" <<<"$1" | head -n1 || true
}

echo "== sign in"
login_page="$(get_page "$BASE_URL/login/")"
login_form="$(grep -oP '<form\b[^>]*>.*?</form>' <<<"$login_page" | grep -m1 'name="password"' || true)"
[[ -n "$login_form" ]] || { echo "sign-in form not found" >&2; exit 1; }
action="$(attr "$(grep -oP '^<form\b[^>]*>' <<<"$login_form")" action)"
[[ "$action" == http* ]] || action="$BASE_URL/${action#/}"
[[ "$action" != "$BASE_URL/" ]] || action="$BASE_URL/login/"
fields=()
while read -r input; do
    name="$(attr "$input" name)"
    [[ -n "$name" ]] && fields+=(--data-urlencode "$name=$(attr "$input" value)")
done < <(grep -oP '<input\b[^>]*type="hidden"[^>]*>' <<<"$login_form")
login_result="$(printf '%s' "$KDE_STORE_PASSWORD" | get_page "${fields[@]}" \
    --data-urlencode "email=$KDE_STORE_USERNAME" --data-urlencode "password@-" "$action")"
if grep -qi 'incorrect login' <<<"$login_result"; then
    echo "sign-in failed: wrong e-mail or password" >&2; exit 1
fi

echo "== read the edit page of product $product"
edit_page="$(get_page "$edit_url")"
if grep -q 'name="password"' <<<"$edit_page"; then
    echo "sign-in failed: the edit page asks to sign in again" >&2; exit 1
fi
data() { # <data-attribute>; URIs get the product id and the base URL
    local value
    value="$(attr "$edit_page" "$1")"
    value="${value//@@project_id@@/$product}"
    [[ "$1" != *-uri || "$value" == http* ]] || value="$BASE_URL/${value#/}"
    printf '%s' "$value"
}
add_uri="$(data data-addpploadfile-uri)"
update_uri="$(data data-updatepploadfile-uri)"
collection="$(data data-ppload-collection-id)"
client_id="$(grep -oP "\\bvar\\s+client_id\\s*=\\s*[\"']\\K[^\"']+" <<<"$edit_page" | head -n1 || true)"
file_uri="$(grep -oP "\\bvar\\s+fileUri\\s*=\\s*[\"']\\K[^\"']+" <<<"$edit_page" | head -n1 || true)"
owner_id="$(grep -oP "form\\.append\\([\"']owner_id[\"'],\\s*[\"']\\K[^\"']+" <<<"$edit_page" | head -n1 || true)"
for var in add_uri update_uri client_id file_uri owner_id; do
    [[ -n "${!var}" ]] || { echo "the edit page has no $var: the store's page changed?" >&2; exit 1; }
done

# The edit page's product form (#add-product-form) as a browser would submit it: its fields in page
# order with their current values (checked boxes, selected options, textarea text), files left out.
# <nul|lines>: NUL-separated name=value pairs, or one name=<JSON string> per line for comparing.
product_form() {
    python3 -I -c '
import html.parser, json, sys

class Form(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.inside, self.fields, self.text, self.select = False, [], None, None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "form":
            self.inside = a.get("id") == "add-product-form"
        if not self.inside or "disabled" in a:
            return
        name = a.get("name")
        if tag == "input" and name:
            kind = (a.get("type") or "text").lower()
            if kind in ("checkbox", "radio"):
                if "checked" in a:
                    self.fields.append((name, a.get("value") or "on"))
            elif kind not in ("file", "submit", "button", "image", "reset"):
                self.fields.append((name, a.get("value") or ""))
        elif tag == "textarea" and name:
            self.text = (name, [])
        elif tag == "select" and name:
            self.select = (name, "multiple" in a, [])
        elif tag == "option" and self.select:
            self.select[2].append([a.get("value"), "selected" in a, []])

    def handle_data(self, data):
        if self.text:
            self.text[1].append(data)
        elif self.select and self.select[2]:
            self.select[2][-1][2].append(data)

    def handle_endtag(self, tag):
        if tag == "form":
            self.inside = False
        elif tag == "textarea" and self.text:
            name, parts = self.text
            text = "".join(parts)
            self.fields.append((name, text[1:] if text.startswith("\n") else text))
            self.text = None
        elif tag == "select" and self.select:
            name, multiple, options = self.select
            values = [v if v is not None else "".join(t).strip() for v, _, t in options]
            chosen = [v for v, (_, sel, _) in zip(values, options) if sel]
            if not chosen and not multiple and values:
                chosen = values[:1]
            self.fields += [(name, v) for v in chosen]
            self.select = None

form = Form()
form.feed(sys.stdin.read())
for name, value in form.fields:
    if sys.argv[1] == "nul":
        sys.stdout.write(name + "=" + value + "\0")
    else:
        print(name + "=" + json.dumps(value))
' "$1"
}

if (( dry_run )); then
    echo "== dry run: signed in, upload endpoints found, nothing changed"
    exit 0
fi

echo "== upload $(basename "$file") ($version)"
uploaded="$(curl -sS --fail-with-body -A "$USER_AGENT" -b "$jar" -c "$jar" --max-time 300 \
    -F "client_id=$client_id" -F "owner_id=$owner_id" -F format=json \
    -F "collection_id=$collection" -F method=post -F "file=@$file" "$file_uri")"
check_status "uploading the file" success "$uploaded"
# Registers the uploaded file with the product: its fields go back as a form.
register=()
while IFS= read -r -d '' field; do
    register+=(--data-urlencode "$field")
done < <(jq -j '.file | to_entries[]
    | "\(.key)=\(.value | if type == "string" then . elif . == null then "" else tojson end)\u0000"' \
    <<<"$uploaded")
registered="$(post_ajax "${register[@]}" "$add_uri")"
check_status "registering the file" ok "$registered"
file_id="$(jq -r '.file.id // empty' <<<"$registered")"
[[ -n "$file_id" ]] || { echo "registering the file returned no file id" >&2; exit 1; }
check_status "setting the file version" ok "$(post_ajax --data-urlencode "file_id=$file_id" \
    --data-urlencode "file_version=$version" --data-urlencode ocs_compatible=1 "$update_uri")"

# Plasma's Get New Widgets only sees "compatible" files (the edit page's checkbox), so unchecking it
# on the older files leaves just this version there, while they stay downloadable on the site.
# Done after the upload, so the product is never left without a file.
echo "== archive the older files"
[[ -n "$collection" ]] || collection="$(jq -r '.file.collection_id // empty' <<<"$uploaded")"
files="$(get_page -H 'Accept: application/json' -H "Referer: $edit_url" \
    "$BASE_URL/p/$product/getfilesajax?format=json&ignore_status_code=1&status=all&perpage=1000&collection_id=$collection")"
check_status "listing the files" success "$files"
while read -r old_id; do
    check_status "archiving file $old_id" ok "$(post_ajax --data-urlencode "file_id=$old_id" \
        --data-urlencode ocs_compatible=0 "$update_uri")"
done < <(jq -r --arg id "$file_id" \
    '.files[] | select((.id | tostring) != $id and (.ocs_compatible | tostring) == "1") | .id' <<<"$files")

if [[ -n "$notes" && -s "$notes" ]]; then
    echo "== changelog $version"
    updates="$(get_page -H 'Accept: application/json' -H "Referer: $edit_url" \
        "$BASE_URL/p/$product/getupdatesajax?format=json&ignore_status_code=1")"
    check_status "reading the changelog" success "$updates"
    update_id="$(jq -r --arg v "$version" \
        'first(.updates[]? | select(.raw_title == $v) | .project_update_id) // empty' <<<"$updates")"
    check_status "saving the changelog" success "$(post_ajax --data-urlencode "title=$version" \
        --data-urlencode "text@$notes" --data-urlencode "update_id=$update_id" \
        "$BASE_URL/p/$product/saveupdateajax")"
fi

echo "== product version $version"
# The product's own Version field (shown on the store page) is not set by the file upload: it is a
# field of the edit page's main form, which saves only as a whole. So the form goes back with its
# current values (what a browser would send) and only the version changed, then is read back.
# Read as is, not with get_page: it joins the lines, and the description's would be lost.
raw_page() { curl -sS --fail-with-body -A "$USER_AGENT" -L --retry 3 -b "$jar" -c "$jar" "$edit_url"; }
page="$(raw_page)"
before="$(product_form lines <<<"$page")"
[[ -n "$before" ]] || { echo "the edit page has no product form: the store's page changed?" >&2; exit 1; }
old_version="$(grep -m1 '^version=' <<<"$before" | cut -d= -f2- | jq -r . || true)"
if [[ "$old_version" == "$version" ]]; then
    echo "already $version"
else
    form=()
    while IFS= read -r -d '' field; do
        [[ "$field" == version=* ]] && field="version=$version"
        form+=(--form-string "$field")
    done < <(product_form nul <<<"$page")
    get_page "${form[@]}" -H "Referer: $edit_url" "$edit_url" >/dev/null
    after="$(raw_page | product_form lines)"
    [[ "$(grep -m1 '^version=' <<<"$after" | cut -d= -f2- | jq -r .)" == "$version" ]] \
        || { echo "saving the product version failed: the edit page still shows another one" >&2; exit 1; }
    # Never prints the values: only the names of fields the round trip changed.
    changed="$(diff <(grep -v '^version=' <<<"$before") <(grep -v '^version=' <<<"$after") \
        | grep -oP '^[<>] \K[^=]+' | sort -u | paste -sd, || true)"
    [[ -z "$changed" ]] || { echo "saving the product version also changed: $changed; check the edit page" >&2; exit 1; }
    echo "$old_version -> $version"
fi

echo "== published $version on https://store.kde.org/p/$product/"
