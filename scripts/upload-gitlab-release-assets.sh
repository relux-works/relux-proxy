#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
PACKAGE_NAME="relux-proxy"

fail() {
    echo "error: $*" >&2
    exit 1
}

"$ROOT/scripts/gitlab-release-preflight.sh"

[[ -n "${CI_JOB_TOKEN:-}" ]] ||
    fail "CI_JOB_TOKEN is required to publish GitLab package assets"
command -v curl >/dev/null 2>&1 ||
    fail "curl is required to publish GitLab package assets"

VERSIONED_DMG="ReluxProxy-$CI_COMMIT_TAG-universal.dmg"
ASSETS=(
    "$VERSIONED_DMG"
    "ReluxProxy.dmg"
    "SHA256SUMS"
)

for asset in "${ASSETS[@]}"; do
    [[ -s "$DIST/$asset" ]] || fail "release asset '$asset' is missing or empty"
done

(
    cd "$DIST"
    shasum -a 256 -c SHA256SUMS
)
cmp -s "$DIST/$VERSIONED_DMG" "$DIST/ReluxProxy.dmg" ||
    fail "stable and versioned DMGs differ before publication"

PACKAGE_URL="$CI_API_V4_URL/projects/$CI_PROJECT_ID/packages/generic/$PACKAGE_NAME/$CI_COMMIT_TAG"
for asset in "${ASSETS[@]}"; do
    if ! upload_status="$(
        curl --disable \
            --silent \
            --show-error \
            --proto '=https' \
            --max-redirs 0 \
            --output /dev/null \
            --write-out '%{http_code}' \
            --header "JOB-TOKEN: $CI_JOB_TOKEN" \
            --upload-file "$DIST/$asset" \
            "$PACKAGE_URL/$asset"
    )"; then
        fail "GitLab package upload failed for '$asset'"
    fi
    [[ "$upload_status" == "201" ]] ||
        fail "GitLab package upload for '$asset' returned unexpected HTTP status '$upload_status'"
    echo "Uploaded $asset to the confirmed Relux GitLab project"
done
