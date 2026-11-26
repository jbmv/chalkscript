#!/bin/sh
# Builds the desktop extension for Claude's desktop app, ChalkScript Studio.mcpb, from
# manifest.json beside this script and the helper inside a built ChalkScript Studio.app, so that
# the extension carries the same signed binary as the app. An .mcpb file is a zip archive with
# manifest.json at its root and the server under server/.
#
# Usage: Studio/Extension/build-extension.sh [APP] [OUTPUT]
#   APP     default: Studio/build/DerivedData/Build/Products/Debug/ChalkScript Studio.app
#   OUTPUT  default: Studio/build/ChalkScript Studio.mcpb
# When the mcpb command (npm package @anthropic-ai/mcpb) is installed, it validates the manifest
# and packs the bundle; otherwise zip packs it.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
studio="$(dirname "$here")"
app="${1:-$studio/build/DerivedData/Build/Products/Debug/ChalkScript Studio.app}"
output="${2:-$studio/build/ChalkScript Studio.mcpb}"
helper="$app/Contents/Helpers/chalkscript-mcp"
[ -x "$helper" ] || { echo "build-extension.sh: no helper at $helper; build the app first (Studio/build.sh)" >&2; exit 66; }

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/server"
cp "$here/manifest.json" "$staging/manifest.json"
# ditto keeps the code signature.
ditto "$helper" "$staging/server/chalkscript-mcp"

mkdir -p "$(dirname "$output")"
output="$(cd "$(dirname "$output")" && pwd)/$(basename "$output")"
rm -f "$output"
if command -v mcpb >/dev/null 2>&1; then
    mcpb pack "$staging" "$output" >&2
else
    (cd "$staging" && zip -q -X -r "$output" manifest.json server)
fi
echo "$output"
