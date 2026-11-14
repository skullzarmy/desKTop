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
    <string>1.0.2</string>
    <key>CFBundleVersion</key>
    <string>3</string>
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

# Build & embed native macOS Screen Saver plugin (.saver)
SAVER_DIR="$CONTENTS_DIR/Library/ScreenSavers/desKTop.saver"
SAVER_CONTENTS="$SAVER_DIR/Contents"
SAVER_MACOS="$SAVER_CONTENTS/MacOS"
SAVER_RESOURCES="$SAVER_CONTENTS/Resources"
mkdir -p "$SAVER_MACOS" "$SAVER_RESOURCES"

if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    sips -s format png -z 100 160 "$DIR/Resources/AppIcon.icns" --out "$SAVER_RESOURCES/thumbnail.png" >/dev/null 2>&1 || true
    sips -s format png -z 200 320 "$DIR/Resources/AppIcon.icns" --out "$SAVER_RESOURCES/thumbnail@2x.png" >/dev/null 2>&1 || true
fi

ARCH="$(uname -m)"
SWIFT_OPT="-Onone"
if [ "$BUILD_CONFIG" = "release" ]; then
    SWIFT_OPT="-O"
fi

echo "Building native macOS Screen Saver bundle (desKTop.saver)..."
swiftc \
    -parse-as-library \
    -emit-library \
    -Xlinker -bundle \
    "$SWIFT_OPT" \
    -target "${ARCH}-apple-macosx14.0" \
    "$DIR/Sources/desKTopScreenSaver/desKTopScreenSaverView.swift" \
    -o "$SAVER_MACOS/desKTopScreenSaver" \
    -framework AppKit \
    -framework AVFoundation \
    -framework ScreenSaver

cat << 'EOF' > "$SAVER_CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>desKTopScreenSaver</string>
    <key>CFBundleIdentifier</key>
    <string>xyz.fafolab.desktop.saver</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>desKTop</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.2</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>desKTopScreenSaverView</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$SAVER_DIR"
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
