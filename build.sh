#!/usr/bin/env bash
# Builds Pier.app into ./build and (optionally) installs or ships it.
#   ./build.sh            build only
#   ./build.sh --install  build, then install to /Applications and launch
#   ./build.sh --release  build, notarize, staple, and produce a shippable zip
#   ./build.sh --publish  --release, then upload the zip to a GitHub release
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Pier"
BUNDLE_ID="so.whatmatters.pier"
EXECUTABLE="Pier"
VERSION="0.1.0"
NOTARY_PROFILE="${NOTARY_PROFILE:-pier-notary}"
TEAM_ID="4P6GX328VY"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
ZIP="$BUILD_DIR/$APP_NAME-$VERSION.zip"

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
  STABLE_SIGNATURE=1
else
  echo "==> Signing (ad-hoc)"
  codesign --force --sign - --identifier "$BUNDLE_ID" \
    --entitlements Pier.entitlements --options runtime --timestamp=none "$APP" 2>/dev/null \
    || codesign --force --sign - --identifier "$BUNDLE_ID" --entitlements Pier.entitlements "$APP"
  STABLE_SIGNATURE=0
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

release() {
  # Gatekeeper blocks an un-notarized app the moment it arrives on another Mac
  # by any route that sets the quarantine flag — download, AirDrop, cloud sync.
  if [[ "$STABLE_SIGNATURE" -eq 0 ]]; then
    echo "!!  Ad-hoc signed — notarization needs a Developer ID certificate." >&2
    exit 1
  fi

  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    if xcrun notarytool history --keychain-profile "matte-notary" >/dev/null 2>&1; then
      NOTARY_PROFILE="matte-notary"
    fi
  fi

  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    cat >&2 <<HELP
!!  No notarization credentials stored under the profile "$NOTARY_PROFILE".

    Create an app-specific password at appleid.apple.com
    (Sign-In and Security > App-Specific Passwords), then run:

      xcrun notarytool store-credentials "$NOTARY_PROFILE" \\
        --apple-id "<your-apple-id>" \\
        --team-id "$TEAM_ID" \\
        --password "<app-specific-password>"

    The password is kept in your keychain, never in this repo.
HELP
    exit 1
  fi

  echo "==> Submitting to Apple for notarization (usually a few minutes)"
  ditto -c -k --keepParent "$APP" "$BUILD_DIR/submit.zip"
  xcrun notarytool submit "$BUILD_DIR/submit.zip" \
    --keychain-profile "$NOTARY_PROFILE" --wait
  rm -f "$BUILD_DIR/submit.zip"

  echo "==> Stapling the ticket"
  xcrun stapler staple "$APP"

  echo "==> Verifying"
  spctl -a -vvv "$APP" 2>&1 | sed 's/^/    /'
  xcrun stapler validate "$APP" 2>&1 | tail -1 | sed 's/^/    /'

  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo
  echo "==> Shippable: $ZIP"
  echo "    Extract with ditto or Archive Utility — never unzip:"
  echo "      ditto -x -k $ZIP ~/Applications"
}

publish() {
  release
  echo "==> Publishing v$VERSION to GitHub"
  gh release create "v$VERSION" "$ZIP" \
    --repo thewhatmatters/pier \
    --title "Pier $VERSION" \
    --notes "Notarized Pier.app. On the work machine: ditto -x -k $APP_NAME-$VERSION.zip ~/Applications && open ~/Applications/Pier.app"
  echo "==> https://github.com/thewhatmatters/pier/releases/tag/v$VERSION"
}

if [[ "${1:-}" == "--release" ]]; then
  release
fi

if [[ "${1:-}" == "--publish" ]]; then
  publish
fi
