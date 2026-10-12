#!/usr/bin/env bash
# Developer ID sign + notarize + staple an assembled .app, then build a signed,
# notarized dmg. Run Scripts/package_app.sh first to produce the .app.
#
# Usage: Scripts/sign-and-notarize.sh [version]
#
# Required env:
#   SIGN_IDENTITY   "Developer ID Application: NAME (TEAMID)"
#                   (auto-detected from the keychain if unset)
#
# Notarization credentials - provide ONE of:
#   NOTARY_PROFILE  name of a stored `notarytool store-credentials` profile
#   -- or --
#   ASC_KEY_ID + ASC_ISSUER_ID + ASC_KEY_PATH   (App Store Connect API .p8 key)
#
# Produces (in dist/):
#   Checkoff.app   (signed, stapled)
#   Checkoff.zip   (notarization artifact / alt download)
#   Checkoff-<version>.dmg   (signed, notarized, stapled)
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0-dev}"
APP_NAME="Checkoff"
APP="dist/${APP_NAME}.app"
ZIP="dist/${APP_NAME}.zip"
DMG="dist/${APP_NAME}-${VERSION}.dmg"

if [[ ! -d "$APP" ]]; then
    echo "error: $APP not found - run Scripts/package_app.sh first" >&2
    exit 1
fi

# Resolve the signing identity.
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning \
        | grep -o 'Developer ID Application: [^"]*' | head -1 || true)"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "error: no Developer ID Application identity found (set SIGN_IDENTITY)" >&2
    exit 1
fi
echo "Signing identity: $SIGN_IDENTITY"

# notarytool credential flags.
notary_args=()
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notary_args=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
    notary_args=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
else
    echo "error: set NOTARY_PROFILE, or ASC_KEY_ID + ASC_ISSUER_ID + ASC_KEY_PATH" >&2
    exit 1
fi

echo "==> Signing the app (hardened runtime, secure timestamp)..."
# No entitlements file: no sandbox, no JIT, nothing that needs one.
codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Notarizing the app..."
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" "${notary_args[@]}" --wait
xcrun stapler staple "$APP"
# Refresh the zip so the stapled ticket is included in the zip download too.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Building the dmg..."
rm -f "$DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "==> Signing + notarizing the dmg..."
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" "${notary_args[@]}" --wait
xcrun stapler staple "$DMG"

echo "==> Verifying Gatekeeper acceptance..."
spctl --assess --type execute --verbose=2 "$APP" || true
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" || true

echo "Done:"
echo "  $APP  (signed, stapled)"
echo "  $ZIP"
echo "  $DMG  (signed, notarized, stapled)"
