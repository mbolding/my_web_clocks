#!/bin/zsh
# Builds the floating desktop clocks with the Swift command-line tools; no Xcode needed.
# Each clock is a folder holding App.swift (the @main entry), Icon.swift (its app icon)
# and its face; Shared/ has the window, menu, accent colour and icon code they all use.
#   ./build.sh                  build every clock into ./build
#   ./build.sh word             build just one (folder name, any case)
#   ./build.sh analog --run     build, then (re)launch it
#   ./build.sh --install        build, copy to ~/Applications, and launch
#
# WidgetKit widget (parked): Analog/Widget is only built and embedded when an Apple
# Development certificate exists (Xcode → Settings → Accounts → Manage Certificates),
# because the widget system ignores ad-hoc signatures.
set -e
cd "$(dirname "$0")"

TARGET=arm64-apple-macos14.0
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 -o '"Apple Development[^"]*"' | tr -d '"' || true)

# folder  executable  bundle id  name
CLOCKS=(
  Analog  ClockWidget  com.mbolding.clockwidget  "Clock Widget"
  Word    WordClock    com.mbolding.wordclock    "Word Clock"
  Command CommandBar   com.mbolding.commandbar   "Command Bar"
  Soma    SomaPlayer   com.mbolding.somaplayer   "Soma Player"
  Timer   DialTimer    com.mbolding.dialtimer    "Dial Timer"
  Launcher WidgetBar   com.mbolding.widgetbar    "Widget Bar"
)

build_clock() {
  local dir=$1 exe=$2 id=$3 name=$4
  local app=build/$exe.app
  local sources=($dir/*.swift)

  rm -rf $app
  mkdir -p $app/Contents/MacOS $app/Contents/Resources

  swiftc -O -parse-as-library -target $TARGET Shared/DesktopClock.swift Shared/Accent.swift ${sources:#*/Icon.swift} \
      -o $app/Contents/MacOS/$exe

  # App icon: draw the clock's own face, then pack the sizes into an .icns. The shared
  # window code comes along for views that use its pieces, like FloatPin.
  swiftc -O -parse-as-library -target $TARGET Shared/MakeIcon.swift Shared/DesktopClock.swift Shared/Accent.swift \
      ${sources:#*/App.swift} -o build/MakeIcon-$exe
  rm -rf build/$exe.iconset
  build/MakeIcon-$exe build/$exe.iconset
  iconutil -c icns build/$exe.iconset -o $app/Contents/Resources/AppIcon.icns

  cat > $app/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$name</string>
    <key>CFBundleIdentifier</key><string>$id</string>
    <key>CFBundleExecutable</key><string>$exe</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <!-- Marks it as one of these widgets, for Widget Bar to find. -->
    <key>DesktopWidget</key><true/>
$([[ -f $dir/InfoPlistExtras.xml ]] && cat $dir/InfoPlistExtras.xml)
</dict>
</plist>
PLIST
  plutil -lint -s $app/Contents/Info.plist

  if [[ -d $dir/Widget && -n "$IDENTITY" ]]; then
    local ext=$app/Contents/PlugIns/${exe}Extension.appex
    mkdir -p $ext/Contents/MacOS
    swiftc -O -parse-as-library -application-extension -target $TARGET \
        Shared/Accent.swift ${sources:#*/(App|Icon).swift} $dir/Widget/*.swift -o $ext/Contents/MacOS/${exe}Extension

    cat > $ext/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$name</string>
    <key>CFBundleDisplayName</key><string>$name</string>
    <key>CFBundleIdentifier</key><string>$id.widget</string>
    <key>CFBundleExecutable</key><string>${exe}Extension</string>
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
    codesign --force --sign "$IDENTITY" --entitlements $dir/Widget/*.entitlements $ext >/dev/null
  fi

  codesign --force --sign "${IDENTITY:--}" $app >/dev/null
  echo "Built $app${IDENTITY:+ (with WidgetKit widget)}"
}

wanted=() action=
for arg in "$@"; do
  case $arg in
    --run|--install) action=$arg ;;
    *) wanted+=(${(L)arg}) ;;
  esac
done

built=0 known=()
for dir exe id name in $CLOCKS; do
  known+=(${(L)dir})
  (( ${#wanted} )) && (( ! ${wanted[(Ie)${(L)dir}]} )) && continue
  build_clock $dir $exe $id $name
  (( ++built ))

  # Quit any running copy and wait for it to go, or open can race the exit and fail.
  if [[ -n $action ]]; then
    pkill -x $exe || true
    while pgrep -qx $exe; do sleep 0.1; done
  fi

  case $action in
    --run)
      open build/$exe.app ;;
    --install)
      rm -rf ~/Applications/$exe.app
      mkdir -p ~/Applications
      cp -R build/$exe.app ~/Applications/
      # Tell Launch Services and the Services menu about it now, for Open With and
      # any Finder service the app declares.
      /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/$exe.app
      /System/Library/CoreServices/pbs -update
      open ~/Applications/$exe.app
      echo "Installed to ~/Applications/$exe.app" ;;
  esac
done

if (( ! built )); then
  echo "No clock named: ${wanted[*]}. Choose from: ${known[*]}" >&2
  exit 1
fi
