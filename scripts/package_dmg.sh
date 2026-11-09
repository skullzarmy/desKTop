#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$DIR/build/desKTop.app"
BUILD_DIR="$DIR/build"
DMG_TEMP="$BUILD_DIR/temp.dmg"
DMG_FINAL="$BUILD_DIR/desKTop.dmg"

if [ ! -d "$APP_DIR" ]; then
    echo "Error: $APP_DIR not found. Run bundle.sh first."
    exit 1
fi

echo "==> 1. Ad-hoc codesigning application bundle..."
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --verbose "$APP_DIR"
echo "✓ Signature valid on disk"

echo "==> 2. Preparing Retina DMG background (dark canvas)..."
TMP_BG_DIR=$(mktemp -d /tmp/dmg_bg_XXXXXX)
if [ -f "$DIR/Resources/Branding/background.tiff" ]; then
    cp "$DIR/Resources/Branding/background.tiff" "$TMP_BG_DIR/background.tiff"
else
    python3 "$DIR/scripts/make_dmg_background.py" "$TMP_BG_DIR"
    tiffutil -cathidpicheck "$TMP_BG_DIR/bg.png" "$TMP_BG_DIR/bg@2x.png" -out "$TMP_BG_DIR/background.tiff"
fi

echo "==> 3. Creating staging disk image..."
hdiutil detach /Volumes/desKTop -force 2>/dev/null || true
rm -f "$DMG_TEMP" "$DMG_FINAL"
hdiutil create -size 40m -fs HFS+ -volname "desKTop" -ov "$DMG_TEMP" > /dev/null

ATTACH_INFO=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TEMP")
DEVICE=$(echo "$ATTACH_INFO" | head -n 1 | awk '{print $1}')
MOUNT_DIR=$(echo "$ATTACH_INFO" | grep -o '/Volumes/.*' | head -n 1)

echo "Attached $DEVICE at $MOUNT_DIR"

echo "==> 4. Staging files into DMG volume..."
cp -R "$APP_DIR" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"
mkdir -p "$MOUNT_DIR/.background"
cp "$TMP_BG_DIR/background.tiff" "$MOUNT_DIR/.background/background.tiff"

if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi

echo "==> 5. Applying Finder window geometry and icon layout..."
osascript << 'APPLESCRIPT' || true
tell application "Finder"
    tell disk "desKTop"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {246, 369, 905, 805}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 108
        set background picture of theViewOptions to file ".background:background.tiff"
        set position of item "desKTop.app" of container window to {160, 215}
        set position of item "Applications" of container window to {500, 215}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT

echo "==> 6. Finalizing disk image..."
sync
hdiutil detach "$DEVICE" -force > /dev/null
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL" > /dev/null
rm -rf "$DMG_TEMP" "$TMP_BG_DIR"

echo "✓ desKTop.dmg generated successfully at: $DMG_FINAL"
ls -lh "$DMG_FINAL"
