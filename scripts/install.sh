#!/usr/bin/env bash
# Installs or upgrades Keeplet for the current user.
# Usage: scripts/install.sh [path/to/keeplet.plasmoid | package-dir]   (default: newest in dist/)
#        scripts/install.sh --remove
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
id="$(sed -n 's/.*"Id": "\(.*\)".*/\1/p' "$root/package/metadata.json")"

if [[ "${1:-}" == "--remove" ]]; then
    exec kpackagetool6 -t Plasma/Applet -r "$id"
fi

src="${1:-$(ls -t "$root"/dist/*.plasmoid 2>/dev/null | head -1)}"
[[ -n "$src" ]] || { echo "nothing to install: run scripts/build.sh first" >&2; exit 1; }

if kpackagetool6 -t Plasma/Applet -s "$id" >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet -u "$src"
else
    kpackagetool6 -t Plasma/Applet -i "$src"
fi

echo "installed $id from $src"
echo "plasmashell caches QML: run 'systemctl --user restart plasma-plasmashell' to reload a widget already on the panel"
