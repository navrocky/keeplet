#!/usr/bin/env bash
# Builds dist/keeplet-<version>.plasmoid inside Docker (or Podman).
# Usage: scripts/build.sh [--no-test]
set -euo pipefail

set -x

root="$(cd "$(dirname "$0")/.." && pwd)"
image="keeplet-build"
run_tests=1

for arg in "$@"; do
    case "$arg" in
        --no-test) run_tests=0 ;;
        -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

engine="$(command -v docker || command -v podman || true)"
[[ -n "$engine" ]] || { echo "docker or podman is required" >&2; exit 1; }

# v1.2.3 tag -> 1.2.3; untagged -> 0.0.0-dev.<commits>+<sha>
version="$(git -C "$root" describe --tags --match 'v[0-9]*' 2>/dev/null | sed 's/^v//' || true)"
if [[ -z "$version" ]]; then
    count="$(git -C "$root" rev-list --count HEAD 2>/dev/null || echo 0)"
    sha="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo nogit)"
    version="0.0.0-dev.${count}+${sha}"
fi

"$engine" build  -t "$image" "$root/docker" >/dev/null

user_args=()
[[ "$(basename "$engine")" == docker ]] && user_args=(--user "$(id -u):$(id -g)")

# label=disable: let the container read the repo on SELinux hosts without relabeling it.
"$engine" run --rm "${user_args[@]}" --security-opt label=disable -v "$root:/src" \
    -e VERSION="$version" -e RUN_TESTS="$run_tests" \
    "$image" bash /src/scripts/package.sh

echo "built: $root/dist/keeplet-$version.plasmoid"
