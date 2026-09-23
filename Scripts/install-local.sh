#!/bin/bash
# Builds your current code and installs it as /Applications/boringNotch.app.
#
# Use this when you want your edits running as the real app, rather than the
# temporary build Xcode makes when you press Cmd+R.
#
#   ./Scripts/install-local.sh

set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="boringNotch.app"

echo "Building..."
xcodebuild -scheme boringNotch -configuration Release -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
    build > /tmp/boringnotch-build.log 2>&1 || {
        echo "Build failed. Last errors:"
        grep -E "error:" /tmp/boringnotch-build.log | head -10
        exit 1
    }

BUILT=$(grep -m1 -o '/.*/Build/Products/Release' /tmp/boringnotch-build.log || true)
[ -n "$BUILT" ] || BUILT=$(xcodebuild -scheme boringNotch -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')

echo "Quitting the running app..."
pkill -f "$APP_NAME/Contents/MacOS/boringNotch" 2>/dev/null || true
sleep 2

echo "Installing to /Applications..."
rm -rf "/Applications/$APP_NAME"
cp -R "$BUILT/$APP_NAME" /Applications/
codesign --force --deep --sign - "/Applications/$APP_NAME" 2>/dev/null

open "/Applications/$APP_NAME"
echo "Done. Your build is installed and running."
