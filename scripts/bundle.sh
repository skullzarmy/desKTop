#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

BUILD_CONFIG="debug"
if [[ "$*" == *"--release"* ]]; then
    BUILD_CONFIG="release"
fi

echo "Building desKTop native macOS binary ($BUILD_CONFIG)..."
if [ "$BUILD_CONFIG" = "release" ]; then
    "$DIR/scripts/build.sh" --product desKTop -c release
    BINARY="$DIR/.build/release/desKTop"
else
    "$DIR/scripts/build.sh" --product desKTop
    BINARY="$DIR/.build/debug/desKTop"
fi

APP_DIR="$DIR/build/desKTop.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy binary
cp "$BINARY" "$MACOS_DIR/desKTop"
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
    <string>a FAFOlab joint. The Unlicense.</string>
</dict>
</plist>
EOF

# Ad-hoc codesign bundle
codesign --force --deep --sign - "$APP_DIR"

if [[ "$*" == *"--zip"* ]] || [ "$BUILD_CONFIG" = "release" ]; then
    cd "$DIR/build"
    rm -f desKTop.zip
    zip -r -y desKTop.zip desKTop.app > /dev/null
    echo "✓ desKTop.zip generated at: $DIR/build/desKTop.zip"
    cd "$DIR"

    "$DIR/scripts/package_dmg.sh"
fi

echo "✓ desKTop.app bundle generated at:"
echo "  $APP_DIR"
