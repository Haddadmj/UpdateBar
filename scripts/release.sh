#!/usr/bin/env bash
# Builds, signs, notarizes, and packages UpdateBar.app into a distributable DMG.
#
# For a fully shippable build you need an Apple Developer account:
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"   # signing identity
#   AC_KEYCHAIN_PROFILE="notary"                        # notarytool profile
#     (create once: xcrun notarytool store-credentials notary \
#        --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>)
#
# Without those, it still produces an ad-hoc-signed, un-notarized DMG for local sharing
# (recipients must right-click → Open the first time).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="UpdateBar"
APP="$ROOT/.build/$APP_NAME.app"
DIST="$ROOT/.build/dist"
DMG="$DIST/$APP_NAME.dmg"
ENTITLEMENTS="$ROOT/Resources/UpdateBar.entitlements"

echo "==> Generating icon…"
swift "$ROOT/scripts/make-icon.swift" "$ROOT/Resources" >/dev/null || echo "   (icon generation skipped)"

echo "==> Building release app bundle…"
"$ROOT/scripts/build-app.sh" release

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "==> Signing with Developer ID + hardened runtime…"
  # Spelled out twice rather than collected into an array: macOS ships bash 3.2,
  # where expanding an empty array under `set -u` is itself an unbound-variable
  # error — and no entitlements file is the normal case here, so the array form
  # failed on every signed build.
  if [ -f "$ENTITLEMENTS" ]; then
    codesign --force --deep --options runtime --timestamp \
      --entitlements "$ENTITLEMENTS" --sign "$DEVELOPER_ID" "$APP"
  else
    codesign --force --deep --options runtime --timestamp \
      --sign "$DEVELOPER_ID" "$APP"
  fi
  codesign --verify --strict --verbose=2 "$APP"
else
  echo "==> No DEVELOPER_ID set — leaving the ad-hoc signature (local use only)."
fi

# Notarization happens twice, and the order is the point. The app is notarized
# and stapled BEFORE it is packaged, so the copy that ships inside the DMG
# carries its own ticket — a staple applied afterwards lands on the build
# output, which nobody installs, and leaves the shipped app needing Apple
# online at first launch. The DMG is then signed and notarized in its own
# right, so `spctl -a -t open` accepts the file people actually download.
if [ -n "${AC_KEYCHAIN_PROFILE:-}" ]; then
  echo "==> Notarizing the app (this can take a few minutes)…"
  ZIP="$ROOT/.build/$APP_NAME.zip"
  rm -f "$ZIP"
  # ditto, not zip: it preserves the bundle's symlinks and extended attributes.
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$AC_KEYCHAIN_PROFILE" --wait
  rm -f "$ZIP"
  echo "==> Stapling the app…"
  xcrun stapler staple "$APP"
fi

echo "==> Building DMG…"
rm -rf "$DIST"; mkdir -p "$DIST"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "   Wrote $DMG"

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "==> Signing the DMG…"
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
fi

if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${AC_KEYCHAIN_PROFILE:-}" ]; then
  echo "==> Notarizing the DMG (this can take a few minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$AC_KEYCHAIN_PROFILE" --wait
  echo "==> Stapling the DMG…"
  xcrun stapler staple "$DMG"
  echo "==> Notarized & stapled ✓"
else
  echo "==> Skipping notarization (need DEVELOPER_ID + AC_KEYCHAIN_PROFILE)."
fi

echo "==> Done: $DMG"
