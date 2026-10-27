#!/bin/zsh
# Builds ClockWidget.app (the floating desktop clock) with the Swift command-line
# tools; no Xcode needed.
#   ./build.sh          build into ./build
#   ./build.sh --run    build, then (re)launch it
#   ./build.sh --install  build, copy to ~/Applications, and launch
#
# WidgetKit widget (parked): ClockWidgetExtension.swift is only built and embedded
# when an Apple Development certificate exists (Xcode → Settings → Accounts →
# Manage Certificates), because the widget system ignores ad-hoc signatures.
set -e
cd "$(dirname "$0")"

TARGET=arm64-apple-macos14.0
APP=build/ClockWidget.app
EXT="$APP/Contents/PlugIns/ClockWidgetExtension.appex"
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 -o '"Apple Development[^"]*"' | tr -d '"' || true)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library -target $TARGET ClockFace.swift ClockWidget.swift \
    -o "$APP/Contents/MacOS/ClockWidget"

# App icon: draw the real dial at 10:09, then pack the sizes into an .icns.
mkdir -p "$APP/Contents/Resources"
swiftc -O -parse-as-library -target $TARGET ClockFace.swift MakeIcon.swift -o build/MakeIcon
rm -rf build/AppIcon.iconset
build/MakeIcon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Clock Widget</string>
    <key>CFBundleIdentifier</key><string>com.mbolding.clockwidget</string>
    <key>CFBundleExecutable</key><string>ClockWidget</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

if [[ -n "$IDENTITY" ]]; then
  mkdir -p "$EXT/Contents/MacOS"
  swiftc -O -parse-as-library -application-extension -target $TARGET ClockFace.swift ClockWidgetExtension.swift \
      -o "$EXT/Contents/MacOS/ClockWidgetExtension"

  cat > "$EXT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Clock Widget</string>
    <key>CFBundleDisplayName</key><string>Clock Widget</string>
    <key>CFBundleIdentifier</key><string>com.mbolding.clockwidget.widget</string>
    <key>CFBundleExecutable</key><string>ClockWidgetExtension</string>
    <key>CFBundlePackageType</key><string>XPC!</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
    <key>DTPlatformName</key><string>macosx</string>
    <key>DTSDKName</key><string>macosx26.4</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
PLIST

  # Sign inside-out; the widget must be sandboxed or macOS won't load it.
  codesign --force --sign "$IDENTITY" --entitlements ClockWidgetExtension.entitlements "$EXT" >/dev/null
fi

codesign --force --sign "${IDENTITY:--}" "$APP" >/dev/null
echo "Built $APP${IDENTITY:+ (with WidgetKit widget)}"

case "$1" in
  --run)
    pkill -x ClockWidget || true
    open "$APP" ;;
  --install)
    pkill -x ClockWidget || true
    rm -rf ~/Applications/ClockWidget.app
    mkdir -p ~/Applications
    cp -R "$APP" ~/Applications/
    open ~/Applications/ClockWidget.app
    echo "Installed to ~/Applications/ClockWidget.app" ;;
esac
