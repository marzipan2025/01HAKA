#!/bin/bash
set -e

APP_NAME="01haka"
DMG_NAME="${APP_NAME}.dmg"
VOL_NAME="${APP_NAME}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BG_IMG="$SCRIPT_DIR/dmg_background.png"

# Find the built app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "01haka.app" -path "*/Build/Products/Release/*" 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    # Try Debug build
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "01haka.app" -path "*/Build/Products/Debug/*" 2>/dev/null | head -1)
fi

if [ -z "$APP_PATH" ]; then
    echo "Error: HanjaWidget.app not found. Please build the project in Xcode first (Product > Archive or Product > Build)."
    exit 1
fi

echo "Found app: $APP_PATH"

# Clean up
TEMP_DIR=$(mktemp -d)
DMG_TEMP="$TEMP_DIR/dmg_temp"
mkdir -p "$DMG_TEMP"

# Copy app
cp -R "$APP_PATH" "$DMG_TEMP/${APP_NAME}.app"

# Create Applications symlink
ln -s /Applications "$DMG_TEMP/Applications"

# Create background directory
mkdir -p "$DMG_TEMP/.background"
cp "$BG_IMG" "$DMG_TEMP/.background/background.png"

# Output path
OUTPUT="$PROJECT_DIR/$DMG_NAME"
rm -f "$OUTPUT"

# Create DMG
hdiutil create -volname "$VOL_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDRW \
    "$TEMP_DIR/temp.dmg"

# Mount
MOUNT_DIR=$(hdiutil attach "$TEMP_DIR/temp.dmg" | grep "/Volumes/" | awk '{print $3}')
echo "Mounted at: $MOUNT_DIR"

# AppleScript to set DMG window appearance
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 740, 580}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 80
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "${APP_NAME}.app" of container window to {195, 240}
        set position of item "Applications" of container window to {445, 240}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Unmount
hdiutil detach "$MOUNT_DIR" -quiet

# Convert to compressed read-only DMG
hdiutil convert "$TEMP_DIR/temp.dmg" -format UDZO -o "$OUTPUT"

# Clean up
rm -rf "$TEMP_DIR"

echo ""
echo "DMG created: $OUTPUT"
echo "Size: $(du -h "$OUTPUT" | awk '{print $1}')"
