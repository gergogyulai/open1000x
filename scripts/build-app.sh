#!/bin/sh
# Builds Open1000X.app (menu bar only) into ./build. mdrctl is bundled at Contents/MacOS/mdrctl.
#   SIGN_IDENTITY=<name> signs with that keychain identity instead of ad-hoc. A stable identity (even
#     a self-signed one, see scripts/make-signing-cert.sh) keeps the Bluetooth permission across updates.
#   UNIVERSAL=1 builds for arm64 and x86_64.
#   DEMO=1 builds a demo variant into ./build/demo: paired device names are masked
#   ("MacBook Pro", "iPhone 16") for screenshots. Regular builds don't contain that code.
set -eu
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
VERSION="${VERSION:-0.1.0}"
APP="build/Open1000X.app"
BUNDLE_ID="dev.open1000x.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
set -- -c "$CONFIG"
if [ "${UNIVERSAL:-0}" = "1" ]; then
    set -- "$@" --arch arm64 --arch x86_64
fi
if [ "${DEMO:-0}" = "1" ]; then
    # Separate build cache so demo objects never end up in a regular build.
    set -- "$@" --scratch-path .build-demo -Xswiftc -DOPEN1000X_DEMO
    APP="build/demo/Open1000X.app"
    BUNDLE_ID="dev.open1000x.app.demo"
fi

swift build "$@" --product Open1000X
swift build "$@" --product mdrctl
BIN="$(swift build "$@" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Open1000X" "$BIN/mdrctl" "$APP/Contents/MacOS/"
# open1000x.icon is an Icon Composer document. actool turns it into Assets.car (Liquid Glass) plus an .icns fallback.
xcrun actool open1000x.icon --compile "$APP/Contents/Resources" --app-icon open1000x \
    --platform macosx --minimum-deployment-target 26.0 \
    --output-partial-info-plist "$(mktemp -d)/icon.plist" > /dev/null

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>Open1000X</string>
    <key>CFBundleDisplayName</key><string>Open1000X</string>
    <key>CFBundleExecutable</key><string>Open1000X</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>open1000x</string>
    <key>CFBundleIconName</key><string>open1000x</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Open1000X talks to your Sony headphones over Bluetooth to change their settings.</string>
    <key>NSHumanReadableCopyright</key><string>Not affiliated with Sony.</string>
</dict>
</plist>
PLIST

# Nested code first, then the bundle.
codesign --force --timestamp=none --sign "$SIGN_IDENTITY" --identifier dev.open1000x.mdrctl "$APP/Contents/MacOS/mdrctl"
codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
echo "Built $APP (signed: $SIGN_IDENTITY)"
