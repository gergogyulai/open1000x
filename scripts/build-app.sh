#!/bin/sh
# Builds Open1000X.app (menu bar only) into ./build. mdrctl is bundled at Contents/MacOS/mdrctl and the
# Control Center controls at Contents/PlugIns/Open1000XControls.appex.
#   SIGN_IDENTITY=<name> signs with that keychain identity instead of ad-hoc. A stable identity (even
#     a self-signed one, see scripts/make-signing-cert.sh) keeps the Bluetooth permission across updates.
#   UNIVERSAL=1 builds for arm64 and x86_64.
set -eu
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
VERSION="${VERSION:-0.1.0}"
APP="build/Open1000X.app"
BUNDLE_ID="dev.open1000x.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ARCHS="arm64"
set -- -c "$CONFIG"
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCHS="arm64 x86_64"
    set -- "$@" --arch arm64 --arch x86_64
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

# The controls are a WidgetKit extension, which SwiftPM can't build. Compile it with swiftc and generate
# the App Intents metadata Xcode would, without which the system can't run the controls' intents. Like
# Xcode, link with _NSExtensionMain as the entry point: it sets up the extension and then calls main.
EXT="$APP/Contents/PlugIns/Open1000XControls.appex"
WORK=".build/controls"
SDK="$(xcrun --show-sdk-path)"
TOOLCHAIN="$(dirname "$(dirname "$(dirname "$(xcrun -f swiftc)")")")"
SOURCES="$(ls "$PWD"/Extensions/Controls/*.swift "$PWD"/Sources/ControlBridge/*.swift)"
if [ "$CONFIG" = release ]; then OPT=-O; else OPT="-Onone -g"; fi
rm -rf "$WORK"
mkdir -p "$WORK" "$EXT/Contents/MacOS" "$EXT/Contents/Resources"
echo "$SOURCES" > "$WORK/sources.txt"
plutil -extract constValueProtocols json -o "$WORK/protocols.json" "$TOOLCHAIN/usr/share/swift/SwiftConstantValues/AppIntents.json"
for arch in $ARCHS; do
    # shellcheck disable=SC2086
    xcrun swiftc -module-name Open1000XControls -parse-as-library -application-extension -swift-version 6 \
        -target "$arch-apple-macos26.0" -sdk "$SDK" $OPT -wmo \
        -emit-const-values-path "$WORK/$arch.swiftconstvalues" \
        -Xfrontend -const-gather-protocols-file -Xfrontend "$WORK/protocols.json" \
        -Xlinker -e -Xlinker _NSExtensionMain \
        $SOURCES -o "$WORK/Open1000XControls-$arch"
done
lipo -create "$WORK"/Open1000XControls-* -output "$EXT/Contents/MacOS/Open1000XControls"
FIRST_ARCH="${ARCHS%% *}"
echo "$PWD/$WORK/$FIRST_ARCH.swiftconstvalues" > "$WORK/constvalues.txt"
xcrun appintentsmetadataprocessor --toolchain-dir "$TOOLCHAIN" --module-name Open1000XControls \
    --sdk-root "$SDK" --xcode-version "$(xcodebuild -version | sed -n 's/Build version //p')" \
    --platform-family macOS --deployment-target 26.0 --target-triple "$FIRST_ARCH-apple-macos26.0" \
    --bundle-identifier "$BUNDLE_ID.controls" --output "$EXT/Contents/Resources" \
    --binary-file "$EXT/Contents/MacOS/Open1000XControls" --source-file-list "$WORK/sources.txt" \
    --swift-const-vals-list "$WORK/constvalues.txt" \
    --compile-time-extraction --deployment-aware-processing --no-app-shortcuts-localization 2> "$WORK/metadata.log" \
    || { cat "$WORK/metadata.log"; exit 1; }

cat > "$EXT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID.controls</string>
    <key>CFBundleName</key><string>Open1000XControls</string>
    <key>CFBundleDisplayName</key><string>Open1000X</string>
    <key>CFBundleExecutable</key><string>Open1000XControls</string>
    <key>CFBundlePackageType</key><string>XPC!</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
PLIST

# Nested code first, then the bundle.
codesign --force --timestamp=none --sign "$SIGN_IDENTITY" --identifier dev.open1000x.mdrctl "$APP/Contents/MacOS/mdrctl"
codesign --force --timestamp=none --sign "$SIGN_IDENTITY" --entitlements Extensions/Controls/Controls.entitlements "$EXT"
codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
echo "Built $APP (signed: $SIGN_IDENTITY)"
