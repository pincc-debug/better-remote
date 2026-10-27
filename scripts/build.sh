#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SIGN_IDENTITY="${BETTER_REMOTE_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    DEVELOPER_IDENTITIES="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p')"
    if [[ "$DEVELOPER_IDENTITIES" == *$'\n'* ]]; then
        echo "error: multiple Developer ID identities; set BETTER_REMOTE_SIGN_IDENTITY" >&2
        exit 1
    fi
    SIGN_IDENTITY="${DEVELOPER_IDENTITIES:-Aquarium Local Code Signing}"
fi
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "error: a fixed signing identity is required to retain permissions" >&2
    exit 1
fi
if ! security find-identity -v -p codesigning | /usr/bin/grep -F "\"$SIGN_IDENTITY\"" >/dev/null; then
    echo "error: signing identity not found: $SIGN_IDENTITY" >&2
    exit 1
fi
swift build -c release --arch arm64 --arch x86_64 -Xswiftc -warnings-as-errors
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
APP="$PWD/dist/Better Remote.app"
DEVELOPER_ID=false
if [[ "$SIGN_IDENTITY" == "Developer ID Application:"* ]]; then DEVELOPER_ID=true; fi
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/RemoteFit-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/BetterRemote" "$APP/Contents/MacOS/BetterRemote"
cp "$PWD/Sources/RemoteFitCore/Resources/device-templates.json" "$APP/Contents/Resources/device-templates.json"
cp "$PWD/Sources/RemoteFitCore/Resources/shortcut-presets.json" "$APP/Contents/Resources/shortcut-presets.json"
cp "$PWD/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.RemoteFit</string>
<key>CFBundleName</key><string>Better Remote</string>
<key>CFBundleDisplayName</key><string>Better Remote</string>
<key>CFBundleExecutable</key><string>BetterRemote</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.8.162</string>
<key>CFBundleVersion</key><string>183</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>NSAppleEventsUsageDescription</key><string>需要你允许 Better Remote 控制“系统事件”，才能切换程序坞</string>
<key>NSHumanReadableCopyright</key><string>Better Remote</string>
<key>SUFeedURL</key><string>https://raw.githubusercontent.com/pincc-debug/better-remote/main/appcast.xml</string>
<key>SUPublicEDKey</key><string>__SU_PUBLIC_ED_KEY__</string>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUScheduledCheckInterval</key><integer>10800</integer>
<key>SUAutomaticallyUpdate</key><false/>
</dict></plist>
PLIST
SU_PUBLIC_ED_KEY="$(tr -d '[:space:]' < "$PWD/scripts/sparkle_public_ed_key.txt")"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SU_PUBLIC_ED_KEY" "$APP/Contents/Info.plist"
# Embed Sparkle.framework and make sure the executable can find it.
SPARKLE_FRAMEWORK="$BIN_DIR/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    SPARKLE_FRAMEWORK="$(find "$PWD/.build/artifacts" -path '*macos*/Sparkle.framework' -maxdepth 6 -type d | head -1)"
fi
mkdir -p "$APP/Contents/Frameworks"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
# Package.swift links with -rpath @executable_path/../Frameworks; fail early if that is lost.
if ! otool -l "$APP/Contents/MacOS/BetterRemote" > "$STAGING/loadcmds.txt" || ! grep -q '@executable_path/../Frameworks' "$STAGING/loadcmds.txt"; then
    echo "error: missing @executable_path/../Frameworks rpath" >&2
    exit 1
fi
xcrun actool "$PWD/assets/branding/AppIcon.icon" \
    --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon AppIcon \
    --output-format human-readable-text \
    --output-partial-info-plist "$STAGING/icon-info.plist"
# Menu bar status item artwork (normal + active), loaded as template images.
cp "$PWD/assets/branding/MenuBarTemplate.png" "$PWD/assets/branding/MenuBarTemplate@2x.png" "$PWD/assets/branding/MenuBarTemplateActive.png" "$PWD/assets/branding/MenuBarTemplateActive@2x.png" "$APP/Contents/Resources/"
cp "$PWD/assets/branding/RewardQR.png" "$APP/Contents/Resources/"
if [ "$DEVELOPER_ID" = true ]; then
    SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY" --options runtime --timestamp)
else
    SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY" --timestamp=none)
fi
# Sign Sparkle inside-out (XPC services, helpers, framework), then the app.
# Timestamp server is flaky; fall back to --timestamp=none rather than shipping linker-signed adhoc.
sign() {
    if ! codesign "${SIGN_FLAGS[@]}" "$@"; then
        echo "warning: codesign with timestamp failed; retrying without timestamp" >&2
        local flags=()
        local skip=0
        for arg in "${SIGN_FLAGS[@]}"; do
            if [ "$skip" = 1 ]; then skip=0; continue; fi
            if [ "$arg" = "--timestamp" ]; then flags+=(--timestamp=none); continue; fi
            if [ "$arg" = "--timestamp=none" ]; then flags+=("$arg"); continue; fi
            flags+=("$arg")
        done
        codesign "${flags[@]}" "$@"
    fi
}
SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for NESTED in "$SPK/XPCServices/Installer.xpc" "$SPK/XPCServices/Downloader.xpc" "$SPK/Autoupdate" "$SPK/Updater.app"; do
    if [ -e "$NESTED" ]; then
        if [[ "$NESTED" == *Downloader.xpc ]]; then
            sign --preserve-metadata=entitlements "$NESTED"
        else
            sign "$NESTED"
        fi
    fi
done
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign --entitlements "$PWD/scripts/BetterRemote.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
# Refuse to install an adhoc / linker-signed build (drops Accessibility / event-tap trust).
if codesign -dv "$APP" 2>&1 | /usr/bin/grep -q 'flags=.*adhoc'; then
    echo "error: app is still adhoc-signed; refusing to ship" >&2
    exit 1
fi
plutil -lint "$APP/Contents/Info.plist"
echo "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$PWD/dist/Better Remote-$VERSION.dmg"
mkdir -p "$STAGING/payload"
ditto "$APP" "$STAGING/payload/Better Remote.app"
ln -s /Applications "$STAGING/payload/Applications"
CANDIDATE="$STAGING/BetterRemote.dmg"
DMG_BG="$PWD/Resources/dmg/background.tiff"
RW_DMG="$STAGING/BetterRemote-rw.dmg"
LAYOUT_OK=false
if [ -f "$DMG_BG" ]; then
    mkdir -p "$STAGING/payload/.background"
    cp "$DMG_BG" "$STAGING/payload/.background/background.tiff"
    hdiutil create -ov -fs HFS+ -volname "Better Remote" -srcfolder "$STAGING/payload" -format UDRW "$RW_DMG"
    MOUNT_DIR="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)"
    if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
        DISK_NAME="$(basename "$MOUNT_DIR")"
        for ATTEMPT in 1 2 3; do
            if osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$DISK_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 520}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "Better Remote.app" of container window to {170, 200}
        set position of item "Applications" of container window to {490, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
            then LAYOUT_OK=true; break; fi
            echo "warning: Finder layout attempt $ATTEMPT failed" >&2
            sleep 2
        done
        SetFile -a V "$MOUNT_DIR/.background" 2>/dev/null || chflags hidden "$MOUNT_DIR/.background" || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$MOUNT_DIR/.DS_Store" ] && break; sleep 1; done
        sync
        for ATTEMPT in 1 2 3 4 5; do
            hdiutil detach "$MOUNT_DIR" -quiet && break
            sleep 2
            [ "$ATTEMPT" = 5 ] && hdiutil detach "$MOUNT_DIR" -force
        done
    fi
fi
if [ "$LAYOUT_OK" = true ]; then
    hdiutil convert "$RW_DMG" -ov -format UDZO -imagekey zlib-level=9 -o "$CANDIDATE"
else
    echo "warning: DMG window layout failed; building a plain DMG" >&2
    rm -rf "$STAGING/payload/.background"
    hdiutil create -ov -fs HFS+ -volname "Better Remote" -srcfolder "$STAGING/payload" -format UDZO "$CANDIDATE"
fi
if [ "$DEVELOPER_ID" = true ]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$CANDIDATE"
    codesign --verify --strict "$CANDIDATE"
fi
# DiskImages may briefly keep a newly created APFS image busy on newer macOS.
VERIFIED=false
for ATTEMPT in 1 2 3 4 5; do
    if hdiutil verify "$CANDIDATE"; then VERIFIED=true; break; fi
    sleep 1
done
if [ "$VERIFIED" != true ]; then exit 1; fi
mv -f "$CANDIDATE" "$DMG"
echo "$DMG"
