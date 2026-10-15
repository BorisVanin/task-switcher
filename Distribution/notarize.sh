#!/bin/bash
#
# Notarize + staple a finished artifact so it opens without warnings on other Macs.
#
#   notarize.sh dist/TaskSwitcher-1.0.dmg
#
# Signing proves who built it; notarization is Apple's separate check that Gatekeeper wants on every
# other Mac. This submits the artifact, waits for the result, staples the ticket (so it also verifies
# offline) and asserts Gatekeeper accepts it.
#
# Credentials (from .envrc), in priority order:
#   1. NOTARY_PROFILE — a notarytool keychain profile. Created once with:
#        xcrun notarytool store-credentials <name> \
#          --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PW
#   2. NOTARY_APPLE_ID + NOTARY_PASSWORD (app-specific password), with NOTARY_TEAM_ID or DEVELOPMENT_TEAM.

source "$(dirname "$0")/common.sh"

ARTIFACT="${1:-}"
[[ -n "$ARTIFACT" ]] || die "usage: notarize.sh <artifact .dmg>"
[[ -e "$ARTIFACT" ]] || die "artifact not found: $ARTIFACT"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    CRED=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
    CRED=(--apple-id "$NOTARY_APPLE_ID" --team-id "${NOTARY_TEAM_ID:-$DEVELOPMENT_TEAM}" --password "$NOTARY_PASSWORD")
else
    die "no notarization credentials: set NOTARY_PROFILE, or NOTARY_APPLE_ID + NOTARY_PASSWORD (see $0)"
fi

log "submitting $(basename "$ARTIFACT") to the Apple notary service (can take a few minutes)"
xcrun notarytool submit "$ARTIFACT" "${CRED[@]}" --wait

log "stapling the ticket"
xcrun stapler staple "$ARTIFACT"

log "verifying"
xcrun stapler validate "$ARTIFACT"
spctl --assess --type open --context context:primary-signature -vv "$ARTIFACT"

log "notarized + stapled $ARTIFACT"
