#!/bin/bash
#
# Build 01haka in Release and package it into a dmg.
#
#   ./make_dmg.sh              build + package into claude_kanji/dist/
#   ./make_dmg.sh --release    ...and publish it as a GitHub release
#
# The dmg is a build artifact: it lives in claude_kanji/dist/ (gitignored) and
# reaches users as a GitHub release asset. It is never committed — the in-app
# updater in UpdateCheck.swift reads the release API's browser_download_url, so
# attaching the dmg to the release is what actually ships an update.
#
set -euo pipefail

APP_NAME="01haka"
SCHEME="HanjaWidget"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"          # claude_kanji/
REPO_DIR="$(dirname "$PROJECT_DIR")"
XCODEPROJ="$PROJECT_DIR/HanjaWidget/HanjaWidget.xcodeproj"
DERIVED="$PROJECT_DIR/build/DerivedData"
DIST="$PROJECT_DIR/dist"
BG_IMG="$SCRIPT_DIR/dmg_background.png"

PUBLISH=0
[ "${1:-}" = "--release" ] && PUBLISH=1

# --- version comes from the project, never from a hand-typed argument --------
VERSION=$(xcodebuild -project "$XCODEPROJ" -scheme "$SCHEME" \
    -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION /{print $2; exit}')
if [ -z "$VERSION" ]; then
    echo "Error: could not read MARKETING_VERSION from the project." >&2
    exit 1
fi
TAG="v$VERSION"
echo "==> 01haka $VERSION ($TAG)"

# --- build -------------------------------------------------------------------
echo "==> Building Release…"
xcodebuild -project "$XCODEPROJ" -scheme "$SCHEME" -configuration Release \
    -derivedDataPath "$DERIVED" build

APP_PATH="$DERIVED/Build/Products/Release/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "Error: $APP_PATH not found after build." >&2; exit 1; }

BUILT_VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
if [ "$BUILT_VERSION" != "$VERSION" ]; then
    echo "Error: built app reports $BUILT_VERSION but project says $VERSION." >&2
    exit 1
fi

# --- package -----------------------------------------------------------------
echo "==> Packaging dmg…"
mkdir -p "$DIST"
OUTPUT="$DIST/$APP_NAME.dmg"
rm -f "$OUTPUT"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
DMG_TEMP="$TEMP_DIR/dmg_temp"
mkdir -p "$DMG_TEMP/.background"

cp -R "$APP_PATH" "$DMG_TEMP/$APP_NAME.app"
ln -s /Applications "$DMG_TEMP/Applications"
cp "$BG_IMG" "$DMG_TEMP/.background/background.png"

hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TEMP" \
    -ov -format UDRW -quiet "$TEMP_DIR/temp.dmg"

MOUNT_DIR=$(hdiutil attach "$TEMP_DIR/temp.dmg" | grep "/Volumes/" | awk '{print $3}')

# Window chrome: icon view, background image, side-by-side app/Applications.
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 740, 580}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 80
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {195, 240}
        set position of item "Applications" of container window to {445, 240}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

hdiutil detach "$MOUNT_DIR" -quiet
hdiutil convert "$TEMP_DIR/temp.dmg" -format UDZO -quiet -o "$OUTPUT"

echo "==> $OUTPUT ($(du -h "$OUTPUT" | awk '{print $1}'))"

[ "$PUBLISH" = "1" ] || {
    echo
    echo "Not published. To ship it:  $0 --release"
    exit 0
}

# --- publish -----------------------------------------------------------------
# Guard rails: the tag must not already exist, and the tree must be committed,
# so a release always points at a reproducible commit.
cd "$REPO_DIR"
if [ -n "$(git status --porcelain)" ]; then
    echo "Error: working tree is dirty — commit before releasing." >&2
    exit 1
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Error: tag $TAG already exists. Bump MARKETING_VERSION first." >&2
    exit 1
fi

echo "==> Publishing $TAG…"
git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" "$OUTPUT" --title "$TAG" --generate-notes

echo "==> Released: $(gh release view "$TAG" --json url -q .url)"
