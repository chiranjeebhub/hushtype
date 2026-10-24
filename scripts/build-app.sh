#!/usr/bin/env bash
# Builds dist/Hushtype.app from the Swift package.
#
# Usage: scripts/build-app.sh [debug|release]
#
# macOS ties Accessibility and Input Monitoring grants to the app's code signature. The default
# ad-hoc signature changes on every build, so you'd have to re-grant after each rebuild. To avoid
# that, sign with a stable identity (a self-signed "Code Signing" certificate works):
#   HUSHTYPE_SIGN_IDENTITY="Hushtype Dev" scripts/build-app.sh
#
# Release builds (scripts/release.sh) also set:
#   HUSHTYPE_VERSION            marketing version, e.g. 0.2.0
#   HUSHTYPE_BUILD              build number, e.g. 12
#   HUSHTYPE_SPARKLE_PUBLIC_KEY Sparkle EdDSA public key; turns on auto-updates
# A "Developer ID Application" identity turns on the hardened runtime and secure timestamps,
# which notarization requires.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Hushtype.app"
IDENTITY="${HUSHTYPE_SIGN_IDENTITY:--}"

cd "$ROOT"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Hushtype" "$APP/Contents/MacOS/Hushtype"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# ditto keeps the framework's symlinks intact.
FRAMEWORK="$BIN_DIR/Sparkle.framework"
if [ ! -d "$FRAMEWORK" ]; then
  FRAMEWORK="$(find .build/artifacts -path '*macos*/Sparkle.framework' -maxdepth 6 -type d | head -1)"
fi
ditto "$FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

PLIST="$APP/Contents/Info.plist"
if [ -n "${HUSHTYPE_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $HUSHTYPE_VERSION" "$PLIST"
fi
if [ -n "${HUSHTYPE_BUILD:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $HUSHTYPE_BUILD" "$PLIST"
fi
if [ -n "${HUSHTYPE_SPARKLE_PUBLIC_KEY:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $HUSHTYPE_SPARKLE_PUBLIC_KEY" "$PLIST"
fi

# App icon from the 512px logo.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size assets/hushtype-icon-512.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  if [ $double -le 512 ]; then
    sips -z $double $double assets/hushtype-icon-512.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  fi
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Sign inside out: Sparkle's helpers, the framework, then the app.
SIGN=(codesign --force --sign "$IDENTITY")
if [[ "$IDENTITY" == "Developer ID Application"* ]]; then
  SIGN+=(--options runtime --timestamp)
fi
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
"${SIGN[@]}" "$SPARKLE/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" --entitlements Resources/Hushtype.entitlements "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP (signed with: $IDENTITY)"
