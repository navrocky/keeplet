#!/usr/bin/env bash
# Stage C0: probes the Keep write protocol on a real account.
#   spike/run-write.sh --dry-run   show the payload that would be sent, send nothing
#   spike/run-write.sh             create, edit, trash and delete two throwaway notes
# Needs the master token saved by spike/run-auth.sh. Output contains no tokens.
set -euo pipefail

dir="${XDG_CACHE_HOME:-$HOME/.cache}/keeplet-spike"
state="$dir/state.json"
report="$dir/write-report.txt"
here="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -s "$state" ]] || ! grep -q '"master_token"' "$state"; then
    echo "No saved session. Run spike/run-auth.sh first (it asks for the oauth_token once)." >&2
    exit 2
fi

mode=run
if [[ "${1:-}" == "--dry-run" ]]; then
    mode=dry
else
    cat <<'EOF'
This writes to your REAL Google Keep account. It will:
  - create two notes titled "keeplet write test (note)" and "keeplet write test (list)",
  - edit them (title, text, color, pin, archive, checklist items, their order, one existing label on the test note only),
  - move them to the trash and delete them for good.
It never modifies a note it did not create. If a step fails it tries to delete what it created;
anything left over has a title starting with "keeplet write test".
EOF
    read -rp "Continue? [y/N] " answer
    [[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "Aborted."; exit 1; }
fi

echo "(output is also saved to $report)"
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 \
    qml6 "$here/write.qml" -- "$state" "$mode" 2>&1 \
    | grep -vE 'propagateSizeHints|kf\.windowsystem|kf\.i18n' | sed -E 's/^qml: //' | tee "$report"
exit "${PIPESTATUS[0]}"
