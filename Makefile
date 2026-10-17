# Task Switcher
#
#   make        generate TaskSwitcher.xcodeproj from project.yml (same as `make gen`)
#   make open   generate, then open the project in Xcode
#   make dmg    Developer ID signed, notarized and stapled dist/TaskSwitcher-<version>-<build>.dmg
#
# Needs DEVELOPMENT_TEAM and PROJECT_IDENTIFIER in the environment (.envrc via direnv — see
# .envrc.default). `make dmg` also needs NOTARY_PROFILE and the "Developer ID Application" certificate
# in the keychain.

.PHONY: gen open dmg check-env

gen: check-env
	mise exec -- xcodegen generate --spec project.yml

open: gen
	open TaskSwitcher.xcodeproj

dmg: gen
	dmg="$$(./Distribution/build-dmg.sh)" && \
	./Distribution/notarize.sh "$$dmg" && \
	./Distribution/set-file-icon.sh "$$dmg"

check-env:
	@test -n "$$DEVELOPMENT_TEAM" || { echo "error: DEVELOPMENT_TEAM is not set (copy .envrc.default to .envrc, then: direnv allow)" >&2; exit 1; }
	@test -n "$$PROJECT_IDENTIFIER" || { echo "error: PROJECT_IDENTIFIER is not set (copy .envrc.default to .envrc, then: direnv allow)" >&2; exit 1; }
