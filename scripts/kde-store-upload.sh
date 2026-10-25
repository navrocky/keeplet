#!/usr/bin/env bash
# Publishes a .plasmoid on the KDE Store (store.kde.org = Pling/opendesktop): replaces the product's
# files with it, sets the file version and adds or updates the changelog entry for that version.
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
for tool in curl jq unzip; do
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
delete_all_uri="$(data data-deletepploadfiles-uri)"
collection="$(data data-ppload-collection-id)"
client_id="$(grep -oP "\\bvar\\s+client_id\\s*=\\s*[\"']\\K[^\"']+" <<<"$edit_page" | head -n1 || true)"
file_uri="$(grep -oP "\\bvar\\s+fileUri\\s*=\\s*[\"']\\K[^\"']+" <<<"$edit_page" | head -n1 || true)"
owner_id="$(grep -oP "form\\.append\\([\"']owner_id[\"'],\\s*[\"']\\K[^\"']+" <<<"$edit_page" | head -n1 || true)"
for var in add_uri update_uri delete_all_uri client_id file_uri owner_id; do
    [[ -n "${!var}" ]] || { echo "the edit page has no $var: the store's page changed?" >&2; exit 1; }
done

if (( dry_run )); then
    echo "== dry run: signed in, upload endpoints found, nothing changed"
    exit 0
fi

# Only one file, so Get New Widgets offers just this version.
if [[ -n "$collection" ]]; then
    echo "== delete the old files"
    check_status "deleting the old files" ok "$(post_ajax -d "" "$delete_all_uri")"
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
check_status "setting the file version" ok \
    "$(post_ajax --data-urlencode "file_id=$file_id" --data-urlencode "file_version=$version" "$update_uri")"

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

echo "== published $version on https://store.kde.org/p/$product/"
