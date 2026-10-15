#!/usr/bin/env bash
# Stage 0 spike A runner. Keeps secrets out of argv and logs:
# state (email, androidId, master token) lives in a 0600 file.
set -euo pipefail

dir="${XDG_CACHE_HOME:-$HOME/.cache}/keeplet-spike"
state="$dir/state.json"
mkdir -p "$dir" && chmod 700 "$dir"

if [[ "${1:-}" == "--reset" ]]; then rm -f "$state"; fi

if [[ ! -s "$state" ]]; then
    read -rp "Google e-mail: " email
    echo "Open https://accounts.google.com/EmbeddedSetup, sign in, then copy the"
    echo "'oauth_token' cookie value (DevTools → Application → Cookies)."
    read -rsp "oauth_token: " token; echo
    android_id=$(head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n')
    (umask 077; printf '{"email":"%s","android_id":"%s","oauth_token":"%s"}' \
        "$email" "$android_id" "$token" > "$state")
fi

QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
QML_XHR_ALLOW_FILE_READ=1 QML_XHR_ALLOW_FILE_WRITE=1 \
    exec qml6 "$(dirname "$0")/auth.qml" -- "$state"
