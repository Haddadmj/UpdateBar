#!/usr/bin/env bash
# Builds UpdateBar and assembles a runnable .app bundle (menu-bar agent).
# Usage: ./scripts/build-app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="UpdateBar"
BUILD_DIR="$ROOT/.build/$CONFIG"
APP_BUNDLE="$ROOT/.build/$APP_NAME.app"

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG" --package-path "$ROOT"

echo "==> Assembling $APP_NAME.app…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# `swift build` compiles against the current SDK but stamps the binary with the
# deployment target as its SDK version, and macOS picks framework behaviour from
# that stamp. Record the SDK it was really built with; the minimum stays as declared.
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$ROOT/Resources/Info.plist")"
SDK_VERSION="$(xcrun --show-sdk-version)"
echo "==> Stamping SDK $SDK_VERSION (minimum macOS $MIN_OS)…"
BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
vtool -set-build-version macos "$MIN_OS" "$SDK_VERSION" -replace -output "$BINARY.stamped" "$BINARY"
mv "$BINARY.stamped" "$BINARY"
chmod +x "$BINARY"

# Ad-hoc sign so the app can run locally without Gatekeeper complaints.
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "==> Done: $APP_BUNDLE"
echo "    Run with: open \"$APP_BUNDLE\"   (look for the icon in the menu bar)"
