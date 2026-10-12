#!/usr/bin/env bash
# Assemble the SwiftPM executable into a .app bundle.
#
# Usage: Scripts/package_app.sh [version] [--universal]
#   version     CFBundleShortVersionString to stamp (default 0.0.0-dev)
#   --universal build a universal (arm64 + x86_64) binary; otherwise host arch
#
# Produces dist/Checkoff.app, ad-hoc signed so it runs on this Mac.
# Scripts/sign-and-notarize.sh replaces that with a Developer ID signature.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0-dev}"
ARCH_ARGS=()
if [[ "${2:-}" == "--universal" ]]; then
    ARCH_ARGS=(--arch arm64 --arch x86_64)
fi

APP_NAME="Checkoff"
APP="dist/${APP_NAME}.app"

echo "Building release binary (${VERSION})..."
swift build -c release ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --product Checkoff
BIN="$(swift build -c release ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --product Checkoff --show-bin-path)/Checkoff"

echo "Assembling ${APP}..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Checkoff"
sed "s/__VERSION__/${VERSION}/g" Resources/Info.plist > "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "Ad-hoc signing..."
codesign --force --sign - --options runtime "$APP"

echo "Done: $APP"
