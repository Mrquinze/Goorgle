#!/bin/zsh
set -euo pipefail

# Builds Goorgle (Release) as a universal (arm64 + x86_64) binary and
# packages it into a drag-to-install .dmg under dist/. xcodebuild's
# signing identity ("Apple Development") is meant only for this Mac's own
# registered devices and can be rejected outright on another Mac, so the
# built app is re-signed ad-hoc afterward — that gets the standard,
# universally-recoverable "unidentified developer" Gatekeeper prompt
# (right-click → Open) on ANY Mac instead. Full no-warning distribution
# still requires a paid Apple Developer Program membership (Developer ID
# signing + notarization), which this script does not do.

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_DIR/Goorgle.app.xcodeproj"
# The Xcode *target* is named "Goorgle.app" (hence the scheme), but
# PRODUCT_NAME is "Goorgle", so the built bundle is a normal "Goorgle.app".
SCHEME="Goorgle.app"
BUILT_PRODUCT_NAME="Goorgle.app"
APP_NAME="Goorgle.app"
EXECUTABLE_NAME="Goorgle"
DIST_DIR="$PROJECT_DIR/dist"
DMG_NAME="Goorgle.dmg"

if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "$(date): $PROJECT_PATH not found — create the Xcode project first (see SETUP.md)." >&2
    exit 1
fi

BUILD_DIR=$(mktemp -d)
STAGING_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR" "$STAGING_DIR"' EXIT

echo "$(date): building $SCHEME (Release, universal)..."
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=macOS' \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -allowProvisioningUpdates \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    build

BUILT_APP=$(find "$BUILD_DIR/Build/Products" -maxdepth 2 -name "$BUILT_PRODUCT_NAME" -print -quit)
if [[ -z "$BUILT_APP" ]]; then
    echo "$(date): build succeeded but $BUILT_PRODUCT_NAME wasn't found under $BUILD_DIR" >&2
    exit 1
fi

echo "$(date): architectures in built binary:"
lipo -info "$BUILT_APP/Contents/MacOS/$EXECUTABLE_NAME"

echo "$(date): staging dmg contents..."
cp -R "$BUILT_APP" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

# Entitlements are passed back in explicitly because re-signing drops whatever
# the build signed in; ad-hoc signatures carry them fine (no team identifier
# needed). The file states app-sandbox=false on purpose — see the comments in
# it. `--options runtime` keeps the Hardened Runtime that xcodebuild applied,
# which a plain re-sign would also drop.
echo "$(date): re-signing ad-hoc for portability to other Macs..."
codesign --force --deep --sign - --options runtime \
    --entitlements "$PROJECT_DIR/Goorgle/Goorgle.entitlements" \
    "$STAGING_DIR/$APP_NAME"

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$DMG_NAME"

echo "$(date): creating $DIST_DIR/$DMG_NAME..."
hdiutil create \
    -volname "Goorgle" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DIST_DIR/$DMG_NAME"

echo "$(date): done — $DIST_DIR/$DMG_NAME"
