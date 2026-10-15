#!/usr/bin/env bash
# Fast dev loop: installs package/ as-is (no Docker build) and opens it in a window.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
id="$(sed -n 's/.*"Id": "\(.*\)".*/\1/p' "$root/package/metadata.json")"

export QT_FORCE_STDERR_LOGGING=1

if command -v plasmoidviewer >/dev/null; then
    exec plasmoidviewer -a "$root/package"
fi

"$root/scripts/install.sh" "$root/package" >/dev/null
exec plasmawindowed "$id"
