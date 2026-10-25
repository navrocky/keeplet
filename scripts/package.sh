#!/usr/bin/env bash
# In-container part of scripts/build.sh. Do not run on the host directly.
set -euo pipefail

: "${VERSION:?}" "${RUN_TESTS:=1}" "${GA_MEASUREMENT_ID:=}" "${GA_API_SECRET:=}"
cd /src

if [[ "$RUN_TESTS" == 1 ]]; then
    echo "== tests"
    qmltestrunner -input tests
fi

echo "== qmllint"
# Plasma/Kirigami modules are not in the image, so warnings caused by
# unresolved imports are disabled; syntax errors still fail the build.
find package -name '*.qml' -print0 \
    | xargs -0 qmllint --unqualified disable --import disable --unused-imports disable \
        --missing-property disable --unresolved-type disable

echo "== package $VERSION"
stage="$(mktemp -d)"
cp -r package "$stage/keeplet"
sed -i "s/\"Version\": \"[^\"]*\"/\"Version\": \"$VERSION\"/" "$stage/keeplet/metadata.json"
# Usage statistics keys (docs/analytics.md); without them the placeholders stay and statistics are off.
if [[ -n "$GA_MEASUREMENT_ID" && -n "$GA_API_SECRET" ]]; then
    [[ "$GA_MEASUREMENT_ID$GA_API_SECRET" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "bad GA_* value" >&2; exit 1; }
    sed -i -e "s/@GA_MEASUREMENT_ID@/$GA_MEASUREMENT_ID/" -e "s/@GA_API_SECRET@/$GA_API_SECRET/" \
        "$stage/keeplet/contents/code/core/analytics.js"
    echo "== usage statistics: on"
else
    echo "== usage statistics: off (no GA_MEASUREMENT_ID / GA_API_SECRET)"
fi

mkdir -p dist
out="dist/keeplet-$VERSION.plasmoid"
rm -f "$out"
(cd "$stage/keeplet" && zip -qr -X "/src/$out" .)
(cd dist && sha256sum "$(basename "$out")" > SHA256SUMS)
rm -rf "$stage"
