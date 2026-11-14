#!/bin/bash
# Capture the README screenshots into docs/screenshots/.
# Needs Screen Recording permission for whatever runs it (Terminal, iTerm…):
#   System Settings → Privacy & Security → Screen & System Audio Recording
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d build/Domark.app ] || ./Scripts/bundle.sh release
OUT=docs/screenshots
FILE="$(pwd)/Fixtures/kitchen-sink.md"
mkdir -p "$OUT"

# Only ever touches the throwaway copy in build/, never the one in /Applications
quit_build_copy() { pkill -f "build/Domark.app/Contents/MacOS/Domark" 2>/dev/null || true; sleep 1; }

window_id() {
  swift - <<'EOF'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
if let w = list.first(where: { ($0["kCGWindowOwnerName"] as? String) == "Domark" && ($0["kCGWindowLayer"] as? Int) == 0 }) {
  print(w["kCGWindowNumber"]!)
}
EOF
}

# Settings are passed as launch arguments, so the user's own preferences are left alone
shot() {
  local name=$1 appearance=$2 mode=$3
  quit_build_copy
  open -n build/Domark.app --args -appearance "$appearance" -viewMode "$mode"
  sleep 2
  open -a "$(pwd)/build/Domark.app" "$FILE"
  sleep 2
  local id; id=$(window_id)
  [ -n "$id" ] || { echo "❌ no Domark window found"; exit 1; }
  screencapture -o -l "$id" "$OUT/$name.png"
  echo "▸ $OUT/$name.png"
}

shot preview-light light preview
shot preview-dark  dark  preview
shot split-light   light split
quit_build_copy
echo "✅ done"
