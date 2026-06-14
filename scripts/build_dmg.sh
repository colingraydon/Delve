#!/usr/bin/env bash
#
# Builds Delve in Release and packages a distributable .dmg into dist/.
#
#   ./scripts/build_dmg.sh
#
# DEFAULT (no env vars): an ad-hoc-signed, un-notarized build. It runs fine, but
# because it isn't notarized by Apple, Gatekeeper warns on first launch. Users
# either right-click the app and choose Open (once), or run:
#     xattr -dr com.apple.quarantine /Applications/Delve.app
#
# CLEAN, WARNING-FREE downloads need an Apple Developer ID ($99/yr program):
#     DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#     NOTARY_PROFILE="delve-notary" \
#     ./scripts/build_dmg.sh
# NOTARY_PROFILE is a notarytool credential stored once with:
#     xcrun notarytool store-credentials delve-notary \
#       --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
PROJECT="${REPO_DIR}/Delve.xcodeproj"
SCHEME="Delve"
APP_NAME="Delve"
BUILD_DIR="${REPO_DIR}/build"
DIST_DIR="${REPO_DIR}/dist"

rm -rf "${BUILD_DIR}"
mkdir -p "${DIST_DIR}"

echo "==> Building ${SCHEME} (Release)"
if [ -n "${DEVELOPER_ID:-}" ]; then
    # Developer ID: sign with the hardened runtime so the build can be notarized.
    xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -configuration Release \
        -derivedDataPath "${BUILD_DIR}" -quiet \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="${DEVELOPER_ID}" \
        OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
        build
else
    # No paid account: ad-hoc sign so the bundle has a signature at least.
    xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -configuration Release \
        -derivedDataPath "${BUILD_DIR}" -quiet \
        CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
        build
fi

APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
[ -d "${APP_PATH}" ] || { echo "error: built app not found at ${APP_PATH}"; exit 1; }

VERSION="$(defaults read "${APP_PATH}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.0")"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
rm -f "${DMG_PATH}"

echo "==> Staging disk image contents"
STAGING="$(mktemp -d)"
cp -R "${APP_PATH}" "${STAGING}/${APP_NAME}.app"
# The /Applications symlink gives the familiar drag-to-install layout.
ln -s /Applications "${STAGING}/Applications"

echo "==> Creating ${DMG_PATH}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING}" -ov -format UDZO "${DMG_PATH}" >/dev/null
rm -rf "${STAGING}"

# Notarize only when both a Developer ID build and a stored profile are present.
if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing (this can take a few minutes)"
    xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
    xcrun stapler staple "${DMG_PATH}"
    echo "==> Notarized and stapled"
fi

echo "==> Done: ${DMG_PATH}"
