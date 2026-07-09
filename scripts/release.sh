#!/bin/bash
#
# Builds, signs, notarizes, and packages Grok.app into a distributable DMG.
#
# One-time setup (see RELEASING.md):
#   xcrun notarytool store-credentials "grok-notary" --apple-id <apple-id> --team-id 9AZ9MMS68X
#
# Usage: ./scripts/release.sh
# Output: dist/Grok-<version>.dmg — signed, notarized, stapled, ready for GitHub Releases.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/Grok-macOS.xcodeproj"
SCHEME="Grok-macOS"
TEAM_ID="9AZ9MMS68X"
NOTARY_PROFILE="grok-notary"
DIST="$REPO_ROOT/dist"
ARCHIVE="$DIST/Grok.xcarchive"
EXPORT_DIR="$DIST/export"
APP="$EXPORT_DIR/Grok.app"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# Submits a file for notarization and fails loudly (with a pointer to the
# notarytool log) if Apple doesn't accept it.
notarize() {
    local file="$1"
    local output id
    step "Notarizing $(basename "$file") — Apple usually takes 1-5 minutes..."
    output="$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || true
    echo "$output"
    if ! echo "$output" | grep -q "status: Accepted"; then
        id="$(echo "$output" | awk '/^  id:/ {print $2; exit}')"
        echo "ERROR: Notarization of $(basename "$file") was not accepted." >&2
        if [[ -n "$id" ]]; then
            echo "Inspect the reason with:" >&2
            echo "  xcrun notarytool log $id --keychain-profile $NOTARY_PROFILE" >&2
        fi
        exit 1
    fi
}

step "Checking prerequisites"
DEV_ID="$(security find-identity -v -p codesigning | sed -n "s/.*\"\(Developer ID Application: .*($TEAM_ID)\)\".*/\1/p" | head -1)"
if [[ -z "$DEV_ID" ]]; then
    echo "ERROR: No 'Developer ID Application' certificate for team $TEAM_ID in the keychain." >&2
    echo "Create one at https://developer.apple.com/account/resources/certificates or via Xcode > Settings > Accounts." >&2
    exit 1
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "ERROR: Notarization credentials '$NOTARY_PROFILE' are missing or invalid." >&2
    echo "One-time setup (needs an app-specific password from https://account.apple.com):" >&2
    echo "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <your-apple-id> --team-id $TEAM_ID" >&2
    exit 1
fi
echo "OK: Developer ID certificate and notary credentials found."

rm -rf "$DIST"
mkdir -p "$DIST"

step "Archiving (Release)"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    -quiet

step "Exporting with Developer ID signing"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$REPO_ROOT/scripts/exportOptions.plist" \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates \
    -quiet

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/Grok-$VERSION.dmg"
echo "Built Grok.app version $VERSION"

# Notarize and staple the app itself so it launches cleanly even offline.
ditto -c -k --keepParent "$APP" "$DIST/Grok.zip"
notarize "$DIST/Grok.zip"
xcrun stapler staple "$APP"

step "Building DMG"
STAGING="$DIST/dmg-staging"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Grok.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Grok" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

# The DMG needs its own Developer ID signature; notarization doesn't add one.
codesign --force --sign "$DEV_ID" --timestamp "$DMG"

notarize "$DMG"
xcrun stapler staple "$DMG"

step "Verifying"
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"
spctl -a -t exec -vv "$APP"
spctl -a -t open --context context:primary-signature -vv "$DMG"

step "SUCCESS"
echo "Ready to upload: $DMG"
echo "  gh release create v$VERSION \"$DMG\" --title \"Grok $VERSION\" --notes \"...\""
