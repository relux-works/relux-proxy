#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
EXPECTED_SIGN_IDENTITY="Developer ID Application: Relux Works, LLC (262RZ595FP)"
EXPECTED_TEAM_ID="262RZ595FP"
RELEASE_TEMP=""
KEYCHAIN_PATH=""

fail() {
    echo "error: $*" >&2
    exit 1
}

require_variable() {
    local name="$1"
    [[ -n "${!name:-}" ]] || fail "required release variable '$name' is not set"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        fail "required release command '$1' is unavailable"
}

cleanup() {
    if [[ -n "$KEYCHAIN_PATH" && -e "$KEYCHAIN_PATH" ]]; then
        security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
    fi
    if [[ -n "$RELEASE_TEMP" && -d "$RELEASE_TEMP" ]]; then
        rm -rf "$RELEASE_TEMP"
    fi
}
trap cleanup EXIT

"$ROOT/scripts/gitlab-release-preflight.sh"

for name in \
    CI_PIPELINE_IID \
    MACOS_CERT_P12_B64 \
    MACOS_CERT_PASSWORD \
    MACOS_KEYCHAIN_PASSWORD \
    ASC_KEY_ID \
    ASC_ISSUER_ID \
    ASC_KEY_P8_B64; do
    require_variable "$name"
done

for command in \
    base64 \
    codesign \
    cmp \
    hdiutil \
    lipo \
    plutil \
    security \
    shasum \
    spctl \
    swift \
    xcrun; do
    require_command "$command"
done

[[ "$CI_PIPELINE_IID" =~ ^[1-9][0-9]*$ ]] ||
    fail "CI_PIPELINE_IID must be a positive integer"

SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:-$EXPECTED_SIGN_IDENTITY}"
[[ "$SIGN_IDENTITY" == "$EXPECTED_SIGN_IDENTITY" ]] ||
    fail "the configured Developer ID is not the Relux Works release identity"

TEMP_ROOT="${TMPDIR:-/tmp}"
TEMP_ROOT="${TEMP_ROOT%/}"
RELEASE_TEMP="$(mktemp -d "$TEMP_ROOT/relux-proxy-release.XXXXXX")"
KEYCHAIN_PATH="$RELEASE_TEMP/relux-release.keychain-db"
CERTIFICATE_PATH="$RELEASE_TEMP/relux-developer-id.p12"
NOTARY_KEY_PATH="$RELEASE_TEMP/AuthKey_$ASC_KEY_ID.p8"

printf '%s' "$MACOS_CERT_P12_B64" | /usr/bin/base64 --decode >"$CERTIFICATE_PATH"
printf '%s' "$ASC_KEY_P8_B64" | /usr/bin/base64 --decode >"$NOTARY_KEY_PATH"
chmod 600 "$CERTIFICATE_PATH" "$NOTARY_KEY_PATH"
[[ -s "$CERTIFICATE_PATH" ]] || fail "decoded Developer ID certificate is empty"
[[ -s "$NOTARY_KEY_PATH" ]] || fail "decoded App Store Connect key is empty"

security create-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERTIFICATE_PATH" \
    -k "$KEYCHAIN_PATH" \
    -P "$MACOS_CERT_PASSWORD" \
    -T /usr/bin/codesign
security set-key-partition-list \
    -S apple-tool:,apple: \
    -s \
    -k "$MACOS_KEYCHAIN_PASSWORD" \
    "$KEYCHAIN_PATH"
security find-identity -v -p codesigning "$KEYCHAIN_PATH" |
    grep -Fq "$SIGN_IDENTITY" ||
    fail "the imported keychain does not contain the Relux Works Developer ID"

VERSION="$CI_COMMIT_TAG" \
    BUILD_NUMBER="$CI_PIPELINE_IID" \
    SIGN_IDENTITY="$SIGN_IDENTITY" \
    SIGN_KEYCHAIN="$KEYCHAIN_PATH" \
    REQUIRE_DEVELOPER_ID=1 \
    "$ROOT/scripts/build-app.sh"

APP="$DIST/ReluxProxy.app"
BINARY="$APP/Contents/MacOS/ReluxProxy"
[[ -x "$BINARY" ]] || fail "the release app executable is missing"
lipo "$BINARY" -verify_arch arm64 x86_64
lipo -archs "$BINARY" >"$DIST/ReluxProxy-$CI_COMMIT_TAG-architectures.txt"

APP_SIGNATURE_REPORT="$DIST/ReluxProxy-$CI_COMMIT_TAG-codesign.txt"
codesign -dv --verbose=4 "$APP" >"$APP_SIGNATURE_REPORT" 2>&1
grep -Fq "Authority=$SIGN_IDENTITY" "$APP_SIGNATURE_REPORT" ||
    fail "the app signature authority is not the Relux Works Developer ID"
grep -Fq "TeamIdentifier=$EXPECTED_TEAM_ID" "$APP_SIGNATURE_REPORT" ||
    fail "the app signature has the wrong Apple team identifier"
codesign --verify --deep --strict --verbose=2 "$APP"

VERSION="$CI_COMMIT_TAG" "$ROOT/scripts/create-dmg.sh"
VERSIONED_DMG="$DIST/ReluxProxy-$CI_COMMIT_TAG-universal.dmg"
[[ -s "$VERSIONED_DMG" ]] || fail "the versioned universal DMG was not created"
codesign --force \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    --keychain "$KEYCHAIN_PATH" \
    "$VERSIONED_DMG"
codesign --verify --strict --verbose=2 "$VERSIONED_DMG"

NOTARY_RESULT="$DIST/ReluxProxy-$CI_COMMIT_TAG-notarization.json"
xcrun notarytool submit "$VERSIONED_DMG" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" \
    --wait \
    --output-format json >"$NOTARY_RESULT"

notary_status="$(plutil -extract status raw -o - "$NOTARY_RESULT")"
[[ "$notary_status" == "Accepted" ]] ||
    fail "Apple notarization returned status '$notary_status'"
submission_id="$(plutil -extract id raw -o - "$NOTARY_RESULT")"
[[ -n "$submission_id" ]] || fail "Apple notarization did not return a submission ID"

NOTARY_LOG="$DIST/ReluxProxy-$CI_COMMIT_TAG-notarization-log.json"
xcrun notarytool log "$submission_id" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" \
    "$NOTARY_LOG"

xcrun stapler staple "$VERSIONED_DMG"
xcrun stapler validate "$VERSIONED_DMG"
codesign --verify --strict --verbose=2 "$VERSIONED_DMG"
spctl -a \
    -t open \
    --context context:primary-signature \
    -v "$VERSIONED_DMG" \
    >"$DIST/ReluxProxy-$CI_COMMIT_TAG-gatekeeper.txt" 2>&1

cp -p "$VERSIONED_DMG" "$DIST/ReluxProxy.dmg"
cmp -s "$VERSIONED_DMG" "$DIST/ReluxProxy.dmg" ||
    fail "the stable-name DMG does not match the versioned DMG"

(
    cd "$DIST"
    shasum -a 256 \
        "ReluxProxy-$CI_COMMIT_TAG-universal.dmg" \
        ReluxProxy.dmg >SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)

versioned_hash_line="$(shasum -a 256 "$VERSIONED_DMG")"
versioned_hash="${versioned_hash_line%% *}"
architectures="$(lipo -archs "$BINARY")"
cat >"$DIST/RELEASE-EVIDENCE.txt" <<EOF
tag=$CI_COMMIT_TAG
commit=$CI_COMMIT_SHA
gitlab_host=$CI_SERVER_HOST
gitlab_project=$CI_PROJECT_PATH
gitlab_project_id=$CI_PROJECT_ID
developer_id=$SIGN_IDENTITY
team_id=$EXPECTED_TEAM_ID
architectures=$architectures
notarization_status=$notary_status
notarization_submission_id=$submission_id
versioned_dmg_sha256=$versioned_hash
EOF

echo "Created signed, notarized, stapled, Gatekeeper-approved $VERSIONED_DMG"
