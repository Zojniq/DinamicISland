#!/usr/bin/env bash
# Builds an arm64-optimised release binary and wraps it in a signed .app bundle.
# Usage: Scripts/bundle.sh && open build/MacIsland.app
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64

APP="build/MacIsland.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/arm64-apple-macosx/release/MacIsland" "$APP/Contents/MacOS/MacIsland"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature: enough for local runs + TCC prompts (Calendar / Apple Events).
codesign --force --deep --sign - "$APP"
echo "✅ Built $APP"
