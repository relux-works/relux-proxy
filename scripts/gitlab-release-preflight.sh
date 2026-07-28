#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_TAG="v0.2.0"
EXCLUDED_GITLAB_HOST="gitlab.wildberries.ru"

fail() {
    echo "error: $*" >&2
    exit 1
}

require_variable() {
    local name="$1"
    [[ -n "${!name:-}" ]] || fail "required CI variable '$name' is not set"
}

runner_has_tag() {
    local expected="$1"
    local normalized
    local tag

    normalized="$(printf '%s' "$CI_RUNNER_TAGS" | tr '[],\"' '    ')"
    for tag in $normalized; do
        if [[ "$tag" == "$expected" ]]; then
            return 0
        fi
    done
    return 1
}

for name in \
    CI_SERVER_HOST \
    CI_SERVER_URL \
    CI_PROJECT_PATH \
    CI_PROJECT_ID \
    CI_PROJECT_URL \
    CI_API_V4_URL \
    CI_COMMIT_TAG \
    CI_COMMIT_SHA \
    CI_COMMIT_REF_PROTECTED \
    CI_PIPELINE_SOURCE \
    CI_RUNNER_TAGS \
    RELUX_GITLAB_HOST \
    RELUX_GITLAB_PROJECT_PATH \
    RELUX_GITLAB_PROJECT_ID \
    RELUX_ACCEPTED_RELEASE_SHA; do
    require_variable "$name"
done

[[ "$CI_SERVER_HOST" != "$EXCLUDED_GITLAB_HOST" ]] ||
    fail "$EXCLUDED_GITLAB_HOST is explicitly excluded from Relux releases"
[[ "$RELUX_GITLAB_HOST" != "$EXCLUDED_GITLAB_HOST" ]] ||
    fail "RELUX_GITLAB_HOST points to the explicitly excluded GitLab instance"
[[ "$CI_SERVER_HOST" == "$RELUX_GITLAB_HOST" ]] ||
    fail "CI_SERVER_HOST does not match the confirmed Relux GitLab hostname"
[[ "$CI_PROJECT_PATH" == "$RELUX_GITLAB_PROJECT_PATH" ]] ||
    fail "CI_PROJECT_PATH does not match the confirmed Relux namespace/project"
[[ "$CI_PROJECT_ID" =~ ^[1-9][0-9]*$ ]] ||
    fail "CI_PROJECT_ID must be a positive numeric GitLab project ID"
[[ "$RELUX_GITLAB_PROJECT_ID" =~ ^[1-9][0-9]*$ ]] ||
    fail "RELUX_GITLAB_PROJECT_ID must be the confirmed positive numeric project ID"
[[ "$CI_PROJECT_ID" == "$RELUX_GITLAB_PROJECT_ID" ]] ||
    fail "CI_PROJECT_ID does not match the confirmed Relux GitLab project ID"
[[ "$CI_SERVER_URL" == "https://$CI_SERVER_HOST" ]] ||
    fail "the release pipeline requires HTTPS on the confirmed GitLab host"
[[ "$CI_PROJECT_URL" == "$CI_SERVER_URL/$CI_PROJECT_PATH" ]] ||
    fail "CI_PROJECT_URL does not identify the confirmed Relux project"
[[ "$CI_API_V4_URL" == "$CI_SERVER_URL"/*"/api/v4" ||
    "$CI_API_V4_URL" == "$CI_SERVER_URL/api/v4" ]] ||
    fail "CI_API_V4_URL is not hosted by the confirmed Relux GitLab instance"
[[ "$CI_COMMIT_TAG" == "$RELEASE_TAG" ]] ||
    fail "this audited pipeline only publishes $RELEASE_TAG"
[[ "$CI_PIPELINE_SOURCE" == "push" ]] ||
    fail "the release must run from a pushed protected tag"
[[ "$CI_COMMIT_REF_PROTECTED" == "true" ]] ||
    fail "$RELEASE_TAG must be configured as a protected tag"
[[ "$CI_COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]] ||
    fail "CI_COMMIT_SHA must be a full 40-character commit SHA"
[[ "$RELUX_ACCEPTED_RELEASE_SHA" =~ ^[0-9a-f]{40}$ ]] ||
    fail "RELUX_ACCEPTED_RELEASE_SHA must be the reviewed full commit SHA"
[[ "$CI_COMMIT_SHA" == "$RELUX_ACCEPTED_RELEASE_SHA" ]] ||
    fail "$RELEASE_TAG does not point to the accepted release commit"

actual_head="$(git -C "$ROOT" rev-parse HEAD)"
[[ "$actual_head" == "$CI_COMMIT_SHA" ]] ||
    fail "the checked-out source does not match CI_COMMIT_SHA"

runner_has_tag "macos" ||
    fail "the selected runner is missing the required 'macos' tag"
runner_has_tag "relux-release" ||
    fail "the selected runner is missing the required 'relux-release' tag"

release_notes="$ROOT/release-notes/$RELEASE_TAG.md"
[[ -s "$release_notes" ]] ||
    fail "release notes are missing at $release_notes"
grep -Fq "SSH config alias" "$release_notes" ||
    fail "release notes must describe SSH config alias behavior"
grep -Fq "concurrent local SOCKS endpoints" "$release_notes" ||
    fail "release notes must describe concurrent local SOCKS endpoints"

echo "Verified release target $CI_SERVER_HOST/$CI_PROJECT_PATH at $CI_COMMIT_SHA"
