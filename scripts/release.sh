#!/usr/bin/env bash
#
# Build, sign (Developer ID), notarize, staple, and package Mimer as a DMG.
#
# One-time prerequisites:
#   1. A "Developer ID Application" certificate in your login keychain:
#        Xcode ▸ Settings ▸ Accounts ▸ (your team) ▸ Manage Certificates ▸ + ▸ Developer ID Application
#      (Verify with: security find-identity -v -p codesigning)
#   2. Stored notarization credentials:
#        xcrun notarytool store-credentials mimer-notary \
#          --apple-id "you@apple.com" --team-id "TEAMID" --password "app-specific-password"
#      (App-specific password: https://account.apple.com ▸ Sign-In and Security ▸ App-Specific Passwords)
#
# Usage:  scripts/release.sh <version>      e.g.  scripts/release.sh 1.0.0
#
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version>}"
NOTARY_PROFILE="${NOTARY_PROFILE:-mimer-notary}"
SCHEME="Mimer"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$DIR/build"
APP="$BUILD/export/Mimer.app"
DMG="$BUILD/Mimer-$VERSION.dmg"

# Resolve the Developer ID identity + team id from the keychain.
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "${IDENTITY:-}" ]; then
  echo "✗ No 'Developer ID Application' certificate found in the keychain."
  echo "  Create one: Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Developer ID Application"
  exit 1
fi
TEAM_ID=$(echo "$IDENTITY" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')
if [ "$(security find-identity -v -p codesigning | grep -c 'Developer ID Application')" -gt 1 ]; then
  echo "⚠ Multiple 'Developer ID Application' identities found — using: $IDENTITY"
fi
echo "▸ Signing as: $IDENTITY  (team $TEAM_ID)"

rm -rf "$BUILD"; mkdir -p "$BUILD"
xcodegen generate --spec "$DIR/project.yml"

echo "▸ Archiving…"
xcodebuild -project "$DIR/Mimer.xcodeproj" -scheme "$SCHEME" -configuration Release \
  -archivePath "$BUILD/Mimer.xcarchive" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$VERSION" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$TEAM_ID" \
  archive

echo "▸ Exporting (Developer ID)…"
cat > "$BUILD/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$BUILD/Mimer.xcarchive" \
  -exportOptionsPlist "$BUILD/export.plist" -exportPath "$BUILD/export"

echo "▸ Verifying signature + hardened runtime…"
codesign --verify --deep --strict --verbose=1 "$APP"
codesign --display --entitlements - "$APP" >/dev/null

echo "▸ Building DMG…"
STAGE="$BUILD/dmg"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"      # drag-to-install
hdiutil create -volname "Mimer" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

echo "▸ Notarizing (this can take a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG" || true

# Update + sign the Sparkle appcast (uses your private EdDSA key from the keychain).
# Required: a release that didn't refresh + sign the appcast would ship while
# auto-update still points at the previous DMG, so fail loudly instead of skipping.
GENAPPCAST=$(find ~/Library/Developer/Xcode/DerivedData/Mimer-*/SourcePackages -name generate_appcast -type f 2>/dev/null | head -1)
if [ -z "${GENAPPCAST:-}" ]; then
  echo "✗ generate_appcast not found (Sparkle artifact). Build the project first so SPM resolves it."
  exit 1
fi
rm -rf "$BUILD/appcast-src"; mkdir -p "$BUILD/appcast-src"; cp "$DMG" "$BUILD/appcast-src/"
"$GENAPPCAST" --download-url-prefix "https://github.com/hasanjafri/Mimer/releases/download/v$VERSION/" \
  "$BUILD/appcast-src" -o "$DIR/appcast.xml"
# Verify this version actually made it into the signed feed.
if ! grep -q "<sparkle:version>$VERSION</sparkle:version>" "$DIR/appcast.xml"; then
  echo "✗ appcast.xml does not contain version $VERSION after generation"
  exit 1
fi
echo "▸ appcast.xml updated + signed — commit + push it after creating the GitHub release"

echo
echo "✅ $DMG"
echo "   signed · notarized · stapled"
echo "   sha256: $(shasum -a 256 "$DMG" | awk '{print $1}')"
echo
echo "Next: gh release create v$VERSION \"$DMG\" --title \"Mimer $VERSION\" --notes \"…\""
