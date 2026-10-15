#!/usr/bin/env bash
# In-container part of scripts/build.sh. Do not run on the host directly.
set -euo pipefail

: "${VERSION:?}" "${RUN_TESTS:=1}"
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

mkdir -p dist
out="dist/keeplet-$VERSION.plasmoid"
rm -f "$out"
(cd "$stage/keeplet" && zip -qr -X "/src/$out" .)
(cd dist && sha256sum "$(basename "$out")" > SHA256SUMS)
rm -rf "$stage"
