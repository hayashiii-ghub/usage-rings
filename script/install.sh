#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT_DIR/script/build.sh"
DESTINATION="$HOME/Applications/Usage Rings.app"
if [[ -e "$DESTINATION" ]]; then
  test "$(plutil -extract CFBundleIdentifier raw "$DESTINATION/Contents/Info.plist")" = "work.hayashigoto.UsageRings"
fi
pkill -x UsageRings >/dev/null 2>&1 || true
mkdir -p "$HOME/Applications"
rm -rf "$DESTINATION"
ditto "$ROOT_DIR/dist/Usage Rings.app" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
python3 "$ROOT_DIR/script/claude-statusline-setup.py" --helper "$DESTINATION/Contents/Helpers/UsageRingsStatusline"
/usr/bin/open "$DESTINATION"
echo "Installed: $DESTINATION"
