#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LocalAIStudio"
PRODUCT_NAME="AIHubApp"
BUNDLE_ID="local.oozoofrog.LocalAIStudio"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"

case "$MODE" in
  run|build-only|--build-only) ;;
  *) echo "usage: $0 [run|build-only]" >&2; exit 2 ;;
esac

cd "$ROOT_DIR"
swift build
BUILD_DIR="$(swift build --show-bin-path)"
BUILD_APP="$BUILD_DIR/$PRODUCT_NAME"
BUILD_CLI="$BUILD_DIR/ai"
RESOURCE_BUNDLE="$(find "$BUILD_DIR" -maxdepth 1 -type d -name '*AIHubCore.bundle' -print -quit)"

if [[ ! -x "$BUILD_APP" || ! -x "$BUILD_CLI" || -z "$RESOURCE_BUNDLE" ]]; then
  echo "Expected SwiftPM products were not built." >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_APP" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
cp "$BUILD_CLI" "$APP_RESOURCES/ai"
chmod +x "$APP_RESOURCES/ai"

cat >"$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>Local AI Studio</string>
  <key>CFBundleDisplayName</key>
  <string>Local AI Studio</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  build-only|--build-only)
    echo "Built app bundle: $APP_BUNDLE"
    ;;
esac
