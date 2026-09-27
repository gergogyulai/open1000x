#!/bin/sh
# Builds Open1000X.app (menu bar only, ad-hoc signed) into ./build.
#   DEMO=1 builds a demo variant into ./build/demo: paired device names are masked
#   ("MacBook Pro", "iPhone 16") for screenshots. Regular builds don't contain that code.
set -eu
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
VERSION="${VERSION:-0.1.0}"
APP="build/Open1000X.app"
BUNDLE_ID="dev.open1000x.app"
set -- -c "$CONFIG"
if [ "${DEMO:-0}" = "1" ]; then
    # Separate build cache so demo objects never end up in a regular build.
    set -- "$@" --scratch-path .build-demo -Xswiftc -DOPEN1000X_DEMO
    APP="build/demo/Open1000X.app"
    BUNDLE_ID="dev.open1000x.app.demo"
fi

swift build "$@" --product Open1000X
BIN="$(swift build "$@" --show-bin-path)/Open1000X"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Open1000X"

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

codesign --force --sign - "$APP"
echo "Built $APP"
