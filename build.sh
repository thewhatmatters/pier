#!/usr/bin/env bash
# Builds Pier.app into ./build and (optionally) installs it.
#   ./build.sh            build only
#   ./build.sh --install  build, then install to /Applications and launch
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Pier"
BUNDLE_ID="so.whatmatters.pier"
EXECUTABLE="Pier"
VERSION="0.1.0"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> Compiling"
swift build -c release

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp ".build/release/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp Sources/Pier/Fonts/*.{ttf,otf,txt} "$APP/Contents/Resources/Fonts/" 2>/dev/null || \
  cp Sources/Pier/Fonts/* "$APP/Contents/Resources/Fonts/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSLocationUsageDescription</key>
    <string>Pier uses your location so the weather tile matches Apple Weather.</string>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Pier uses your location so the weather tile matches Apple Weather.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>Pier shows today’s events on the calendar tile.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Pier shows today’s events on the calendar tile.</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 WhatMatters. All rights reserved.</string>
    <key>ATSApplicationFontsPath</key><string>Fonts</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -m1 "Developer ID Application" | sed -E 's/.*"(.*)"/\1/')"
if [[ -z "$SIGN_ID" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/')"
fi

if [[ -n "$SIGN_ID" ]]; then
  echo "==> Signing with: $SIGN_ID"
  # WeatherKit is restricted (POSIX 163 without the App ID capability).
  # Calendar/Location are required under hardened runtime or TCC never prompts.
  codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" \
    --entitlements Pier.entitlements --options runtime --timestamp "$APP"
else
  echo "==> Signing (ad-hoc)"
  codesign --force --sign - --identifier "$BUNDLE_ID" \
    --entitlements Pier.entitlements --options runtime --timestamp=none "$APP" 2>/dev/null \
    || codesign --force --sign - --identifier "$BUNDLE_ID" --entitlements Pier.entitlements "$APP"
fi

echo "==> Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
  echo "==> Installing to /Applications"
  pkill -x "$EXECUTABLE" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  open "/Applications/$APP_NAME.app"
  echo "==> Launched. Look for the capsule at the bottom of the screen."
fi
