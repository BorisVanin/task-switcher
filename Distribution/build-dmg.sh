#!/bin/bash
#
# Build a signed .dmg: a disk named "Task Switcher" with the app icon, whose window shows the switcher
# example over the desktop picture, the app on the left, an arrow, and the Applications shortcut on the
# right (install = drag). Prints the .dmg path on STDOUT; notarize it with notarize.sh.
#
#   1. export the Developer ID signed app            (export-app.sh)
#   2. let the app draw the window background        (--render-dmg-background)
#   3. build the image and its Finder window layout  (dmgbuild + dmg-settings.py)
#   4. sign the .dmg with Developer ID Application

source "$(dirname "$0")/common.sh"

BACKGROUND_DIR="${WORK}/background"

# 1. Distribution-signed app ----------------------------------------------------
app="$("$(dirname "$0")/export-app.sh")"
VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$app/Contents/Info.plist")"
DMG="${DIST_DIR}/TaskSwitcher-${VERSION}-${BUILD}.dmg"

# 2. Window background: the same switcher example as in Settings, 1x + 2x in one TIFF ----
log "drawing the window background"
rm -rf "$BACKGROUND_DIR"
mkdir -p "$BACKGROUND_DIR"
"$app/Contents/MacOS/Task Switcher" --render-dmg-background "$BACKGROUND_DIR" \
    || die "the app could not draw the disk image background"
tiffutil -cathidpicheck "$BACKGROUND_DIR/background.png" "$BACKGROUND_DIR/background@2x.png" \
    -out "$BACKGROUND_DIR/background.tiff" >&2

# 3. Image + window layout, from the settings file ------------------------------
log "creating disk image"
rm -f "$DMG"
(cd "$PROJECT_HOME" && mise exec -- dmgbuild \
    -s "$PROJECT_HOME/Distribution/dmg-settings.py" \
    -D app="$app" \
    -D icon="$app/Contents/Resources/AppIcon.icns" \
    -D background="$BACKGROUND_DIR/background.tiff" \
    "$VOLUME_NAME" "$DMG") >&2

# 4. Sign the container (with a secure timestamp, for notarization) -------------
log "signing dmg with '${APP_SIGN_ID}'"
codesign --force --sign "$APP_SIGN_ID" --timestamp "$DMG" >&2

log "built ${DMG}"
echo "$DMG"
