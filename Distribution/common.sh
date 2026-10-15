#!/bin/bash
#
# Shared setup for the distribution scripts (export-app / build-dmg / notarize). Source it; don't run it:
#
#   source "$(dirname "$0")/common.sh"
#
# `log` prints to STDERR: the build scripts keep STDOUT clean so the artifact path is their only
# output and callers can capture it with $(...).
#
# Environment (from .envrc via direnv, see .envrc.default):
#   DEVELOPMENT_TEAM   (required)  10-character Apple Developer Team ID.
#   NOTARY_PROFILE                 notarytool keychain profile (see notarize.sh).
#   APP_SIGN_ID                    signing identity for the .dmg (default: Developer ID Application).

set -euo pipefail

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Outside a direnv-loaded shell, load .envrc from the project so the scripts also work standalone.
if [[ -z "${DEVELOPMENT_TEAM:-}" ]] && command -v direnv >/dev/null 2>&1; then
    eval "$(cd "$PROJECT_HOME" && direnv export bash 2>/dev/null)" || true
fi
[[ -n "${DEVELOPMENT_TEAM:-}" ]] || die "DEVELOPMENT_TEAM is not set (copy .envrc.default to .envrc, then: direnv allow)"

APP_PROJECT="${PROJECT_HOME}/TaskSwitcher.xcodeproj"
APP_SCHEME="TaskSwitcher"
APP_NAME="Task Switcher.app"
VOLUME_NAME="Task Switcher"
DIST_DIR="${PROJECT_HOME}/dist"
APP_SIGN_ID="${APP_SIGN_ID:-Developer ID Application}"

# Intermediate files (archive, export, background) stay out of the project folder; only the finished
# .dmg goes to dist/.
WORK="${TMPDIR:-/tmp}/taskswitcher-dist"
EXPORT_DIR="${WORK}/export"
APP_EXPORTED="${EXPORT_DIR}/${APP_NAME}"

mkdir -p "$DIST_DIR"
