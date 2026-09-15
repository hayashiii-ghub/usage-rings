#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
CONFIGURATION="${CONFIGURATION:-release}"
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP="$ROOT_DIR/dist/Usage Rings.app"
WIDGET="$APP/Contents/PlugIns/UsageRingsWidget.appex"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$WIDGET/Contents/MacOS" "$WIDGET/Contents/Resources"
cp "$BIN_DIR/UsageRings" "$APP/Contents/MacOS/UsageRings"
cp "$BIN_DIR/UsageRingsWidget" "$WIDGET/Contents/MacOS/UsageRingsWidget"
cp -R "$BIN_DIR/UsageRings_UsageCore.bundle" "$APP/Contents/Resources/"
cp -R "$BIN_DIR/UsageRings_UsageCore.bundle" "$WIDGET/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>work.hayashigoto.UsageRings</string>
<key>CFBundleExecutable</key><string>UsageRings</string>
<key>CFBundleName</key><string>Usage Rings</string>
<key>CFBundleDisplayName</key><string>Usage Rings</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleURLTypes</key><array><dict>
<key>CFBundleURLName</key><string>work.hayashigoto.UsageRings.usage</string>
<key>CFBundleURLSchemes</key><array><string>usagerings</string></array>
</dict></array>
</dict></plist>
PLIST
cat > "$WIDGET/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>work.hayashigoto.UsageRings.Widget</string>
<key>CFBundleExecutable</key><string>UsageRingsWidget</string>
<key>CFBundleName</key><string>Usage Rings</string>
<key>CFBundleDisplayName</key><string>Usage Rings</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
<key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string></dict>
</dict></plist>
PLIST
codesign --force --sign - --entitlements "$ROOT_DIR/Assets/Widget.entitlements" "$WIDGET"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
