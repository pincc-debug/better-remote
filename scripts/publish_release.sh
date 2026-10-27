#!/bin/bash
# Creates GitHub release v$VERSION with BOTH assets: Better-Remote-$VERSION.dmg (appcast URL) and
# Better-Remote.dmg (stable releases/latest/download URL). Fails loudly if either is missing or differs.
# Usage: scripts/publish_release.sh "<release notes>"   (run after notarize.sh and release_appcast.sh)
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="${BETTER_REMOTE_RELEASE_REPO:-pincc-debug/better-remote}"
APP="$PWD/dist/Better Remote.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
NOTES="${1:?usage: $0 \"<release notes>\"}"
VERSIONED="$PWD/dist/Better-Remote-$VERSION.dmg"
ALIAS="$PWD/dist/Better-Remote.dmg"
for f in "$VERSIONED" "$ALIAS"; do [ -f "$f" ] || { echo "error: missing $f (run release_appcast.sh)" >&2; exit 1; }; done
SHA="$(shasum -a 256 "$VERSIONED" | cut -c1-64)"
[ "$SHA" = "$(shasum -a 256 "$ALIAS" | cut -c1-64)" ] || { echo "error: $ALIAS differs from $VERSIONED" >&2; exit 1; }
xcrun stapler validate "$VERSIONED" >/dev/null || { echo "error: dmg not stapled" >&2; exit 1; }

if gh release view "v$VERSION" -R "$REPO" >/dev/null 2>&1; then
    gh release upload "v$VERSION" "$VERSIONED" "$ALIAS" -R "$REPO" --clobber
else
    gh release create "v$VERSION" "$VERSIONED" "$ALIAS" -R "$REPO" --title "Better Remote $VERSION" --notes "$NOTES"
fi

# Verify both asset names exist on the release with the same SHA-256.
fail=0
for name in "Better-Remote-$VERSION.dmg" Better-Remote.dmg; do
    digest="$(gh release view "v$VERSION" -R "$REPO" --json assets --jq ".assets[] | select(.name==\"$name\") | .digest")"
    if [ "$digest" != "sha256:$SHA" ]; then echo "ERROR: asset $name on v$VERSION is missing or wrong (got '${digest:-none}', want sha256:$SHA)" >&2; fail=1; fi
done
[ "$fail" -eq 0 ] || { echo "ERROR: release v$VERSION is incomplete; fix before announcing" >&2; exit 1; }
echo "release v$VERSION: both assets uploaded, sha256 $SHA"
echo "https://github.com/$REPO/releases/tag/v$VERSION"
