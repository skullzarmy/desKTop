#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "Building desKTop native macOS binary..."
"$DIR/scripts/build.sh" --product desKTop

APP_DIR="$DIR/build/desKTop.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy binary
cp "$DIR/.build/debug/desKTop" "$MACOS_DIR/desKTop"
chmod +x "$MACOS_DIR/desKTop"

# Copy resources, icons & branding
if [ -d "$DIR/Resources" ]; then
    cp -R "$DIR/Resources/"* "$RESOURCES_DIR/"
fi
if [ -d "$DIR/Sources/desKTopApp/Resources" ]; then
    cp -R "$DIR/Sources/desKTopApp/Resources/"* "$RESOURCES_DIR/"
fi

# Create Info.plist with LSUIElement to completely prevent Dock icon
cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>desKTop</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>xyz.fafolab.desktop</string>
    <key>CFBundleName</key>
    <string>desKTop</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 FAFOlab (a FAFOlab joint). The Unlicense.</string>
</dict>
</plist>
EOF

echo "✓ desKTop.app background accessory bundle generated at:"
echo "  $APP_DIR"
