#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Arthur Cissac
#
# Builds Hublot for others to download: the app (./build.sh, signed with the
# Developer ID of Fork/identity.sh's team), a DMG holding it and a link to
# Applications, the DMG signed, then notarized and stapled with the
# notarytool keychain profile "hublot-notary" when it exists.
#
# The profile is made once, by hand (it asks for an app-specific password,
# which never goes through this script):
#   xcrun notarytool store-credentials hublot-notary --apple-id <Apple ID> --team-id <team>
#
# Usage: ./Fork/release.sh [--skip-build]   (dist/Hublot-<version>.dmg)
set -euo pipefail
umask 022
cd "$(dirname "$0")/.."
source Fork/identity.sh

PROFILE="${HUBLOT_NOTARY_PROFILE:-hublot-notary}"
APP="build/stage/$FORK_APP_NAME.app"

[[ "${1:-}" == "--skip-build" ]] || ./build.sh
[[ -d "$APP" ]] || { echo "✗ $APP not found: run ./build.sh first" >&2; exit 1; }
codesign --verify --deep --strict "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
mkdir -p dist
DMG="dist/$FORK_APP_NAME-$VERSION.dmg"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/$FORK_APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$FORK_APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($FORK_TEAM_ID)" \
    | head -1 | sed -E 's/.*"(.+)"/\1/')
[[ -n "$IDENTITY" ]] || { echo "✗ No Developer ID Application certificate for team $FORK_TEAM_ID" >&2; exit 1; }
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl -a -t open --context context:primary-signature -v "$DMG"
    echo "✓ Notarized: $DMG"
else
    echo "⚠︎ Not notarized: no notarytool profile \"$PROFILE\" in the keychain. Make it once with:"
    echo "  xcrun notarytool store-credentials $PROFILE --apple-id <your Apple ID> --team-id $FORK_TEAM_ID"
fi
shasum -a 256 "$DMG"
echo "✓ $DMG ($VERSION)"
