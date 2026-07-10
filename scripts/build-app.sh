#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.0-dev}"
VERSION="${VERSION#v}"
SHORT_VERSION="${VERSION%%-*}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
APP_NAME="ReluxProxy"
BUNDLE="$ROOT/dist/$APP_NAME.app"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Relux Works, LLC (262RZ595FP)}"

cd "$ROOT"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

BUILD_ARGUMENTS=(-c release)
if [[ "${UNIVERSAL:-1}" == "1" ]]; then
    BUILD_ARGUMENTS+=(--arch arm64 --arch x86_64)
fi

swift build "${BUILD_ARGUMENTS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path)"
cp "$BIN_DIR/ReluxProxy" "$BUNDLE/Contents/MacOS/ReluxProxy"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
swift "$ROOT/scripts/generate-icon.swift" "$BUNDLE/Contents/Resources/ReluxProxy.icns"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" "$BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$BUNDLE/Contents/Info.plist"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$BUNDLE"
elif security find-identity -v -p codesigning | grep -Fq "$SIGN_IDENTITY"; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$BUNDLE"
else
    echo "warning: '$SIGN_IDENTITY' not found; using an ad-hoc signature" >&2
    codesign --force --sign - "$BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$BUNDLE"
echo "Built $BUNDLE ($VERSION, build $BUILD_NUMBER)"
