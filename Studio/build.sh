#!/bin/sh
# Builds ChalkScript Studio from a clean checkout: generates the Xcode project with XcodeGen,
# builds the app with xcodebuild into Studio/build, and builds the desktop extension for Claude's
# desktop app from the app's helper. Prints the paths of the app and the extension.
#
# Usage: Studio/build.sh [Debug|Release]   (default: Debug)
#
# Debug is the default because Swift 6.4.2 crashes optimising the engine (in CopyPropagation, on
# EntryFiller.lookup in Sources/ChalkScript/Document/Wording.swift), so Release does not build
# with that compiler; `swift build -c release` fails the same way.
set -eu
cd "$(dirname "$0")"
configuration="${1:-Debug}"
command -v xcodegen >/dev/null || { echo "build.sh: xcodegen is needed (brew install xcodegen)" >&2; exit 69; }
xcodegen generate --quiet
xcodebuild -project ChalkScriptStudio.xcodeproj -scheme ChalkScriptStudio -configuration "$configuration" \
    -derivedDataPath build/DerivedData -quiet build
app="$PWD/build/DerivedData/Build/Products/$configuration/ChalkScript Studio.app"
echo "$app"
Extension/build-extension.sh "$app"
