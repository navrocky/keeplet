#!/usr/bin/env bash
# Runs the UI tests in tests-ui/ against the real Plasma/Kirigami QML modules installed on this machine.
# They use synthetic mouse events on the real screens (drag and drop, clicks); the build container
# doesn't have those modules, so these don't run in scripts/build.sh.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

runner="$(command -v qmltestrunner6 || command -v qmltestrunner)"
[[ -n "$runner" ]] || { echo "qmltestrunner (Qt 6 declarative tools) is required" >&2; exit 1; }

QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}" QT_FORCE_STDERR_LOGGING=1 \
    exec "$runner" -input tests-ui "$@"
