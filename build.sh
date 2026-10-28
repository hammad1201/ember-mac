#!/bin/bash
# Builds build/Ember.app (Apple Silicon, macOS 26+). Usage: ./build.sh [--install]
#
# The desktop widget needs a real signing identity: macOS won't load an ad-hoc signed widget,
# and the app shares data with it through a team-prefixed App Group. The first
# "Apple Development" identity in your keychain is used; override with SIGN_IDENTITY=... .
# Without one, the app is ad-hoc signed and built without the widget.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Ember.app
APPEX="$APP/Contents/PlugIns/EmberWidget.appex"
TARGET=arm64-apple-macos26.0
rm -rf build
mkdir -p build/obj "$APP/Contents/MacOS" "$APP/Contents/Resources"

SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Apple Development' | sed -E 's/.*"(.*)"/\1/' || true)}"
TEAM_ID=""
if [[ -n "$SIGN_IDENTITY" ]]; then
  TEAM_ID=$(security find-certificate -c "$SIGN_IDENTITY" -p | openssl x509 -noout -subject | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p')
fi
APP_GROUP="${TEAM_ID:+$TEAM_ID.com.hammad.Ember}"

echo "› Compiling app"
clang -O2 -mmacosx-version-min=26.0 -c Sources/SMC.c -o build/obj/SMC.o
swiftc -O -swift-version 5 -target $TARGET \
  -import-objc-header Sources/Bridge.h \
  Sources/*.swift Sources/Shared/*.swift build/obj/SMC.o \
  -framework IOKit \
  -o "$APP/Contents/MacOS/Ember"

echo "› Icon"
swift Scripts/make_icon.swift build/icon.png
ICONSET=build/AppIcon.iconset
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size build/icon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) build/icon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
sed "s/__APP_GROUP__/$APP_GROUP/" Resources/Info.plist > "$APP/Contents/Info.plist"

if [[ -n "$TEAM_ID" ]]; then
  echo "› Compiling widget (team $TEAM_ID)"
  mkdir -p "$APPEX/Contents/MacOS"
  # Extensions must start in Foundation's _NSExtensionMain (as Xcode links them),
  # which sets up the extension runtime before calling the Swift @main.
  swiftc -O -swift-version 5 -target $TARGET -parse-as-library -application-extension \
    -Xlinker -e -Xlinker _NSExtensionMain \
    Widget/*.swift Sources/Shared/*.swift \
    -o "$APPEX/Contents/MacOS/EmberWidget"
  sed "s/__APP_GROUP__/$APP_GROUP/" Resources/Widget-Info.plist > "$APPEX/Contents/Info.plist"

  echo "› Compiling background agent"
  # Keeps the widget's snapshot fresh while the app is closed (registered with SMAppService.agent).
  swiftc -O -swift-version 5 -target $TARGET \
    -import-objc-header Sources/Bridge.h \
    Agent/main.swift Sources/Sensors.swift Sources/Power.swift Sources/SnapshotWriter.swift \
    Sources/Shared/Snapshot.swift build/obj/SMC.o \
    -framework IOKit \
    -o "$APP/Contents/MacOS/EmberAgent"
  mkdir -p "$APP/Contents/Library/LaunchAgents"
  cp Resources/Agent.plist "$APP/Contents/Library/LaunchAgents/com.hammad.Ember.agent.plist"

  cat > build/widget.entitlements <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.application-groups</key><array><string>$APP_GROUP</string></array>
</dict></plist>
PLIST
  cat > build/app.entitlements <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.application-groups</key><array><string>$APP_GROUP</string></array>
</dict></plist>
PLIST

  echo "› Signing with $SIGN_IDENTITY"
  codesign --force --sign "$SIGN_IDENTITY" --entitlements build/widget.entitlements "$APPEX"
  codesign --force --sign "$SIGN_IDENTITY" --entitlements build/app.entitlements \
    --identifier com.hammad.Ember.agent "$APP/Contents/MacOS/EmberAgent"
  codesign --force --sign "$SIGN_IDENTITY" --entitlements build/app.entitlements "$APP"
else
  echo "› No Apple Development identity found: ad-hoc signing, widget skipped"
  codesign --force --sign - "$APP"
fi

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/Ember.app
  cp -R "$APP" ~/Applications/
  # Two registered copies confuse the widget daemon, so keep only the installed one.
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSREGISTER" -u "$PWD/$APP" 2>/dev/null || true
  "$LSREGISTER" -f -R ~/Applications/Ember.app
  # Restart the background agent (if registered) so it runs the new binary.
  launchctl kickstart -k "gui/$(id -u)/com.hammad.Ember.agent" 2>/dev/null || true
  echo "› Installed to ~/Applications/Ember.app"
fi
echo "✓ $APP"
