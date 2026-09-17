#!/bin/bash
# Install Domark into /Applications and let Finder know about it.
# Usage: ./Scripts/install.sh                 → /Applications
#        ./Scripts/install.sh ~/Applications  → current user only
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="${1:-/Applications}"
APP="$DEST/Domark.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

./Scripts/bundle.sh release

if [ ! -w "$DEST" ]; then
  echo "❌ cannot write to $DEST — try: sudo $0 $DEST"
  exit 1
fi

# Quit any running copy first, otherwise it cannot be overwritten
pkill -f "Domark.app/Contents/MacOS/Domark" 2>/dev/null || true
sleep 1

echo "▸ unregistering the previous copy (keeps Open With from listing duplicates)"
"$LSREGISTER" -u "$APP" 2>/dev/null || true
"$LSREGISTER" -u "$(pwd)/build/Domark.app" 2>/dev/null || true

echo "▸ installing to $APP"
rm -rf "$APP"
cp -R build/Domark.app "$APP"

echo "▸ registering with Finder"
"$LSREGISTER" -f "$APP"

echo
echo "✅ installed: $APP"
echo
echo "Opening .md files:"
echo "  • right-click a file → Open With → Domark"
echo "  • to make it the default for every .md file:"
echo "      right-click → Get Info → \"Open with\" → Domark → \"Change All…\""
echo "  • from the terminal:  open -a Domark file.md"
