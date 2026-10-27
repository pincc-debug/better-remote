#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/Better Remote.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$PWD/dist/Better Remote-$VERSION.dmg"
PROFILE="${BETTER_REMOTE_NOTARY_PROFILE:-better-remote-notary}"
RESULT="$PWD/dist/notarization-$VERSION.json"
LOG="$PWD/dist/notarization-$VERSION-log.json"

codesign --verify --deep --strict "$APP"
codesign --verify --strict "$DMG"
if ! codesign -dv --verbose=2 "$APP" 2>&1 | grep '^Authority=Developer ID Application:' > /dev/null; then
    echo "error: build with a Developer ID Application identity first" >&2
    exit 1
fi

SUBMIT_STATUS=0
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --output-format json > "$RESULT" || SUBMIT_STATUS=$?
ID="$(plutil -extract id raw -o - "$RESULT" 2>/dev/null || true)"
STATUS="$(plutil -extract status raw -o - "$RESULT" 2>/dev/null || true)"
if [ -n "$ID" ]; then
    xcrun notarytool log "$ID" --keychain-profile "$PROFILE" "$LOG"
fi
if [ "$SUBMIT_STATUS" -ne 0 ] || [ "$STATUS" != Accepted ]; then
    cat "$RESULT"
    echo "error: notarization did not finish with Accepted; see $LOG" >&2
    exit 1
fi

xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict "$APP"
codesign --verify --strict "$DMG"
if command -v syspolicy_check > /dev/null; then
    syspolicy_check distribution "$APP"
fi
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
hdiutil verify "$DMG"
shasum -a 256 "$DMG"
echo "$DMG"
