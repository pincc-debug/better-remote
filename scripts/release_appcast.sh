#!/bin/bash
# 为已公证、已装订的 dmg 生成更新签名，并把这一版写进 dist/appcast.xml（只写本地，不发布）。
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/Better Remote.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
DMG="$PWD/dist/Better Remote-$VERSION.dmg"
ASSET="Better-Remote-$VERSION.dmg"
URL="https://github.com/pincc-debug/better-remote/releases/download/v$VERSION/$ASSET"
APPCAST="${BETTER_REMOTE_APPCAST:-$PWD/dist/appcast.xml}"
SIGN_UPDATE="$(find "$PWD/.build/artifacts" -path '*/bin/sign_update' -type f | head -1)"
[ -x "$SIGN_UPDATE" ] || { echo "error: sign_update not found; run swift build first" >&2; exit 1; }
xcrun stapler validate "$DMG" >/dev/null || { echo "error: $DMG is not notarized+stapled; run scripts/notarize.sh" >&2; exit 1; }

# sign_update reads the private EdDSA key from the login keychain and prints: sparkle:edSignature="..." length="..."
SIG_ATTRS="$("$SIGN_UPDATE" "$DMG")"
echo "$SIG_ATTRS" | grep -q 'sparkle:edSignature=' || { echo "error: sign_update failed" >&2; exit 1; }

# Chinese release notes: the README section for this version.
NOTES="$(awk -v v="## $VERSION" '($0==v || index($0,v" ")==1){f=1;next} /^## /{if(f)exit} f' README.md \
    | sed -n 's/^- //p' | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's|.*|<li>&</li>|' | tr -d '\n')"
[ -n "$NOTES" ] || NOTES="<li>问题修复与体验改进。</li>"
PUBDATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

ITEM="    <item>
      <title>$VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[<h3>$VERSION 更新内容</h3><ul>$NOTES</ul>]]></description>
      <enclosure url=\"$URL\" type=\"application/octet-stream\" $SIG_ATTRS />
    </item>"

if [ ! -f "$APPCAST" ]; then
    cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Better Remote</title>
    <language>zh-CN</language>
<!-- ITEMS -->
  </channel>
</rss>
XML
fi
python3 - "$APPCAST" "$BUILD" "$ITEM" <<'PY'
import re, sys
path, build, item = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path, encoding="utf-8").read()
s = re.sub(r'\n    <item>(?:(?!</item>).)*?<sparkle:version>%s</sparkle:version>.*?</item>' % re.escape(build), '', s, flags=re.S)
s = s.replace('<!-- ITEMS -->', '<!-- ITEMS -->\n' + item, 1)
open(path, "w", encoding="utf-8").write(s)
PY
xmllint --noout "$APPCAST"
cp "$DMG" "$PWD/dist/$ASSET"
# Stable alias for releases/latest/download/Better-Remote.dmg (uploaded by scripts/publish_release.sh).
cp "$DMG" "$PWD/dist/Better-Remote.dmg"
echo "appcast: $APPCAST"
echo "asset:   $PWD/dist/$ASSET  ->  $URL"
