#!/bin/bash
# Assemble Domark.app from the binary that `swift build` produces.
# It has to run as a real .app to get a proper menu bar, Dock icon and window.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Domark.app"

echo "▸ building (${CONFIG})…"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Domark"

echo "▸ assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Domark"
cp Bundle/Info.plist "$APP/Contents/Info.plist"

# Icon — generated on demand if missing. Edit its look in Icon/make-icon.swift
[ -f Icon/Domark.icns ] || swift Icon/make-icon.swift
cp Icon/Domark.icns "$APP/Contents/Resources/Domark.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature — required on Apple Silicon once the bundle has been modified
echo "▸ signing…"
codesign --force --sign - --timestamp=none "$APP"

# Deliberately NOT registered with LaunchServices: build/ is the throwaway test copy.
# Scripts/install.sh registers the one in /Applications so Finder lists it only once.

echo "✅ $(pwd)/$APP"
