#!/usr/bin/env bash
# Builds a signed, notarized Hushtype release: dist/Hushtype-<version>.zip (for Sparkle),
# dist/Hushtype-<version>.dmg (for people downloading it) and dist/appcast.xml.
#
# Usage: scripts/release.sh <version> [build-number]
#
# Needs (see RELEASING.md):
#   HUSHTYPE_SIGN_IDENTITY       "Developer ID Application: Your Name (TEAMID)", in the keychain
#   Notarization, either:
#     HUSHTYPE_NOTARY_PROFILE    a profile saved with `xcrun notarytool store-credentials`, or
#     ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH   an App Store Connect API key (.p8)
#   HUSHTYPE_SPARKLE_PUBLIC_KEY  Sparkle EdDSA public key (goes into Info.plist)
#   SPARKLE_PRIVATE_KEY          the matching private key, to sign the update
#                                (or leave unset to use the one generate_keys saved in the keychain)
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version> [build-number]}"
BUILD="${2:-$(git rev-list --count HEAD)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="chiranjeebhub/hushtype"
cd "$ROOT"

: "${HUSHTYPE_SIGN_IDENTITY:?set HUSHTYPE_SIGN_IDENTITY to your Developer ID Application identity}"
: "${HUSHTYPE_SPARKLE_PUBLIC_KEY:?set HUSHTYPE_SPARKLE_PUBLIC_KEY (see RELEASING.md)}"
if [[ "$HUSHTYPE_SIGN_IDENTITY" != "Developer ID Application"* ]]; then
  echo "Releases must be signed with a Developer ID Application certificate." >&2
  exit 1
fi

notarize() {
  if [ -n "${HUSHTYPE_NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$1" --keychain-profile "$HUSHTYPE_NOTARY_PROFILE" --wait
  else
    : "${ASC_KEY_ID:?set HUSHTYPE_NOTARY_PROFILE or ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH}"
    xcrun notarytool submit "$1" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
  fi
}

HUSHTYPE_VERSION="$VERSION" HUSHTYPE_BUILD="$BUILD" scripts/build-app.sh release
APP="dist/Hushtype.app"
ZIP="dist/Hushtype-$VERSION.zip"
DMG="dist/Hushtype-$VERSION.dmg"

# Notarize the app and staple the ticket so it opens offline too.
ditto -c -k --keepParent "$APP" dist/notarize.zip
notarize dist/notarize.zip
xcrun stapler staple "$APP"
rm dist/notarize.zip
ditto -c -k --keepParent "$APP" "$ZIP"

# A disk image with an Applications shortcut, for downloads from the website or GitHub.
STAGE="$(mktemp -d)"
ditto "$APP" "$STAGE/Hushtype.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Hushtype" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --force --sign "$HUSHTYPE_SIGN_IDENTITY" --timestamp "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

# Sign the update for Sparkle and write a one-item appcast pointing at the GitHub release.
SIGN_UPDATE="$(find .build/artifacts -name sign_update -type f -perm -u+x | head -1)"
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  KEY_FILE="$(mktemp)"
  chmod 600 "$KEY_FILE"
  printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE"
  SIGNATURE="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$ZIP")"
  rm -f "$KEY_FILE"
else
  SIGNATURE="$("$SIGN_UPDATE" "$ZIP")"
fi
URL="https://github.com/$REPO/releases/download/v$VERSION/Hushtype-$VERSION.zip"
cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Hushtype</title>
    <item>
      <title>Hushtype $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="$URL" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
XML

echo "Release $VERSION ($BUILD) ready:"
ls -lh "$ZIP" "$DMG" dist/appcast.xml
