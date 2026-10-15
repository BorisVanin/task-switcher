#!/bin/bash
#
# Produce a Developer ID signed "Task Switcher.app" ready for the disk image. Prints its path on STDOUT.
#
#   1. archive the Release configuration
#   2. export it with a Developer ID export — the step that makes it notarizable
#   3. verify the result is what the notary service wants
#
# A plain `xcodebuild build` is not enough: it carries com.apple.security.get-task-allow and has no
# secure timestamp, and the notary service rejects both. The Developer ID export re-signs for
# distribution: strips get-task-allow, adds the timestamp, keeps the hardened runtime.

source "$(dirname "$0")/common.sh"

ARCHIVE="${WORK}/${APP_SCHEME}.xcarchive"
EXPORT_PLIST="${WORK}/ExportOptions.plist"

rm -rf "$WORK"
mkdir -p "$EXPORT_DIR"

# 1. Archive (universal: Apple silicon + Intel) ---------------------------------
log "archiving ${APP_SCHEME} (Release)"
xcodebuild -project "$APP_PROJECT" -scheme "$APP_SCHEME" \
    -configuration Release -archivePath "$ARCHIVE" \
    -destination "generic/platform=macOS" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    archive >&2

# 2. Developer ID export --------------------------------------------------------
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>${DEVELOPMENT_TEAM}</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
PLIST

log "exporting (Developer ID distribution signature)"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" -exportOptionsPlist "$EXPORT_PLIST" >&2

[[ -d "$APP_EXPORTED" ]] || die "exported app not found: $APP_EXPORTED"

# 3. Verify it is notarizable ---------------------------------------------------
log "verifying distribution signature"
codesign --verify --strict --verbose=2 "$APP_EXPORTED" >&2
# Captured into variables: `... | grep -q` could SIGPIPE codesign, and pipefail would fail the script.
sig="$(codesign -dvvv "$APP_EXPORTED" 2>&1 || true)"
ents="$(codesign -d --entitlements - "$APP_EXPORTED" 2>/dev/null || true)"
echo "$sig" | grep -q 'flags=.*runtime' || die "hardened runtime missing"
echo "$ents" | grep -q 'get-task-allow' && die "get-task-allow present — not notarizable"
log "ok: $(echo "$sig" | grep -E '^Authority=' | head -1 | sed 's/Authority=//'), hardened runtime, no get-task-allow"

echo "$APP_EXPORTED"
