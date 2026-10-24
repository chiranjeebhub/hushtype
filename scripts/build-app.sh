#!/usr/bin/env bash
# Builds dist/Hushtype.app from the Swift package.
#
# Usage: scripts/build-app.sh [debug|release]
#
# macOS ties Accessibility and Input Monitoring grants to the app's code signature. The default
# ad-hoc signature changes on every build, so you'd have to re-grant after each rebuild. To avoid
# that, create a self-signed "Code Signing" certificate in Keychain Access and pass its name:
#   HUSHTYPE_SIGN_IDENTITY="Hushtype Dev" scripts/build-app.sh
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Hushtype.app"
IDENTITY="${HUSHTYPE_SIGN_IDENTITY:--}"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Hushtype"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Hushtype"
cp Resources/Info.plist "$APP/Contents/Info.plist"

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

codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP (signed with: $IDENTITY)"
