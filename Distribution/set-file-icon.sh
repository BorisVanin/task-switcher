#!/bin/bash
#
# Give the finished .dmg file the app icon in Finder.
#
#   set-file-icon.sh dist/TaskSwitcher-1.0.2-17.dmg
#
# Runs last, after notarize.sh: the icon is Finder metadata on the file (a resource fork and the
# custom-icon flag), outside the signed and stapled contents. It survives AirDrop, Finder copies and
# zip archives; uploading the bare .dmg to a web server drops it, as for every custom file icon.

source "$(dirname "$0")/common.sh"

DMG="${1:-}"
[[ -f "$DMG" ]] || die "usage: set-file-icon.sh <file .dmg>"
ICON="${APP_EXPORTED}/Contents/Resources/AppIcon.icns"
[[ -f "$ICON" ]] || die "app icon not found: $ICON (run build-dmg.sh first)"

result="$(osascript -l JavaScript - "$ICON" "$DMG" <<'JXA'
function run(argv) {
    ObjC.import("AppKit");
    const image = $.NSImage.alloc.initWithContentsOfFile(argv[0]);
    return $.NSWorkspace.sharedWorkspace.setIconForFileOptions(image, argv[1], 0);
}
JXA
)"
[[ "$result" == "true" ]] || die "could not set the icon of $DMG"
log "app icon set on $(basename "$DMG")"
