#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPECTED_REPOSITORY="relux-works/relux-proxy"
EXPECTED_TAG="v0.2.0"
EXPECTED_RUNNER_NAME="relux-proxy-release"
EXPECTED_SIGN_IDENTITY="Developer ID Application: Relux Works, LLC (262RZ595FP)"
EXPECTED_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

fail() {
    echo "error: $*" >&2
    exit 1
}

require_variable() {
    local name="$1"
    [[ -n "${!name:-}" ]] || fail "required release variable '$name' is not set"
}

for name in \
    GITHUB_EVENT_NAME \
    GITHUB_REPOSITORY \
    GITHUB_REF_TYPE \
    GITHUB_REF_NAME \
    GITHUB_SHA \
    GITHUB_RUN_NUMBER \
    RUNNER_NAME \
    RUNNER_OS \
    RUNNER_ARCH \
    DEVELOPER_DIR \
    SIGN_IDENTITY \
    MACOS_CERT_P12 \
    ASC_KEY_ID \
    ASC_ISSUER_ID \
    ASC_KEY_P8; do
    require_variable "$name"
done

[[ "$GITHUB_EVENT_NAME" == "push" ]] ||
    fail "the release workflow requires a tag push event"
[[ "$GITHUB_REPOSITORY" == "$EXPECTED_REPOSITORY" ]] ||
    fail "the release workflow is running for an unexpected GitHub repository"
[[ "$GITHUB_REF_TYPE" == "tag" ]] ||
    fail "the release workflow requires a tag ref"
[[ "$GITHUB_REF_NAME" == "$EXPECTED_TAG" ]] ||
    fail "the release workflow accepts only tag '$EXPECTED_TAG'"
[[ "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]] ||
    fail "GITHUB_SHA must be a full lowercase commit SHA"
[[ "$GITHUB_RUN_NUMBER" =~ ^[1-9][0-9]*$ ]] ||
    fail "GITHUB_RUN_NUMBER must be a positive integer"

[[ "$RUNNER_NAME" == "$EXPECTED_RUNNER_NAME" ]] ||
    fail "the release workflow is not running on the dedicated release runner"
[[ "$RUNNER_OS" == "macOS" ]] ||
    fail "the release workflow requires a macOS runner"
[[ "$RUNNER_ARCH" == "X64" ]] ||
    fail "the release workflow requires an x64 runner"
[[ "$DEVELOPER_DIR" == "$EXPECTED_DEVELOPER_DIR" ]] ||
    fail "DEVELOPER_DIR does not select the full Xcode installation"
[[ "$SIGN_IDENTITY" == "$EXPECTED_SIGN_IDENTITY" ]] ||
    fail "the configured release identity is not the Relux Works Developer ID"

checked_out_sha="$(env -u DEVELOPER_DIR git -C "$ROOT" rev-parse HEAD)"
[[ "$checked_out_sha" == "$GITHUB_SHA" ]] ||
    fail "the checked-out commit does not match GITHUB_SHA"

echo "Validated GitHub release context for $GITHUB_REPOSITORY at $GITHUB_SHA on $RUNNER_NAME"
