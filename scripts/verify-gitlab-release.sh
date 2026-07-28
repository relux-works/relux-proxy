#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
VERIFY_DIR="$DIST/published-verification"
PACKAGE_NAME="relux-proxy"
MAX_REDIRECTS=5
REQUEST_TEMP=""

fail() {
    echo "error: $*" >&2
    exit 1
}

cleanup() {
    if [[ -n "$REQUEST_TEMP" && -d "$REQUEST_TEMP" ]]; then
        rm -rf "$REQUEST_TEMP"
    fi
}
trap cleanup EXIT

url_origin() {
    local url="$1"
    local remainder
    local authority

    case "$url" in
        https://*) ;;
        *) return 1 ;;
    esac
    if [[ "$url" =~ [[:space:][:cntrl:]] ]] ||
        [[ "$url" == *\\* || "$url" == *"#"* ]]; then
        return 1
    fi

    remainder="${url#https://}"
    authority="${remainder%%[/?#]*}"
    [[ -n "$authority" && "$authority" != *"@"* ]] || return 1
    printf 'https://%s' "$authority"
}

is_gitlab_origin() {
    local origin

    origin="$(url_origin "$1")" || return 1
    [[ "$origin" == "$CI_SERVER_URL" ]]
}

trim_http_value() {
    local value="$1"

    while [[ "$value" == " "* || "$value" == $'\t'* ]]; do
        value="${value#?}"
    done
    while [[ "$value" == *" " || "$value" == *$'\t' ]]; do
        value="${value%?}"
    done
    printf '%s' "$value"
}

extract_redirect_location() {
    local headers="$1"
    local line
    local header_name
    local value
    local location=""
    local count=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" == *":"* ]] || continue
        header_name="${line%%:*}"
        header_name="$(printf '%s' "$header_name" | tr '[:upper:]' '[:lower:]')"
        if [[ "$header_name" == "location" ]]; then
            value="$(trim_http_value "${line#*:}")"
            location="$value"
            count=$((count + 1))
        fi
    done <"$headers"

    [[ "$count" -eq 1 && -n "$location" ]] ||
        fail "redirect response must contain exactly one non-empty Location header"
    if [[ "$location" =~ [[:space:][:cntrl:]] ]] ||
        [[ "$location" == *\\* || "$location" == *"#"* ]]; then
        fail "redirect Location is malformed"
    fi
    printf '%s' "$location"
}

resolve_redirect() {
    local current_url="$1"
    local location="$2"
    local origin

    case "$location" in
        https://*)
            url_origin "$location" >/dev/null ||
                fail "redirect Location is not a valid HTTPS URL"
            printf '%s' "$location"
            ;;
        *://*)
            fail "redirect URL must use HTTPS"
            ;;
        //*)
            fail "scheme-relative redirect Locations are not allowed"
            ;;
        /*)
            origin="$(url_origin "$current_url")" ||
                fail "cannot resolve redirect from a malformed current URL"
            printf '%s%s' "$origin" "$location"
            ;;
        *)
            fail "redirect Location must be an absolute HTTPS URL or absolute path"
            ;;
    esac
}

http_get() {
    local url="$1"
    local headers="$2"
    local body="$3"
    local status
    local curl_arguments=(
        --disable
        --silent
        --show-error
        --proto '=https'
        --max-redirs 0
        --dump-header "$headers"
        --output "$body"
        --write-out '%{http_code}'
    )

    if is_gitlab_origin "$url"; then
        curl_arguments+=(--header "JOB-TOKEN: $CI_JOB_TOKEN")
    fi

    if ! status="$(curl "${curl_arguments[@]}" "$url")"; then
        fail "HTTPS request failed"
    fi
    printf '%s' "$status"
}

fetch_release_metadata() {
    local url="$1"
    local destination="$2"
    local headers="$REQUEST_TEMP/release.headers"
    local body="$REQUEST_TEMP/release.body"
    local status

    is_gitlab_origin "$url" ||
        fail "the Release API URL is not on the confirmed GitLab origin"
    status="$(http_get "$url" "$headers" "$body")"
    [[ "$status" == "200" ]] ||
        fail "the GitLab Release API returned unexpected HTTP status '$status'"
    mv "$body" "$destination"
    rm -f "$headers"
}

fetch_release_asset() {
    local initial_url="$1"
    local destination="$2"
    local current_url="$initial_url"
    local destination_name="${destination##*/}"
    local redirect_count=0
    local headers
    local body
    local status
    local location
    local next_url

    is_gitlab_origin "$initial_url" ||
        fail "the initial release asset URL is not on the confirmed GitLab origin"

    while true; do
        headers="$REQUEST_TEMP/$destination_name.headers"
        body="$REQUEST_TEMP/$destination_name.body"
        rm -f "$headers" "$body"
        status="$(http_get "$current_url" "$headers" "$body")"

        case "$status" in
            200)
                mv "$body" "$destination"
                rm -f "$headers"
                return 0
                ;;
            301 | 302 | 303 | 307 | 308)
                location="$(extract_redirect_location "$headers")"
                next_url="$(resolve_redirect "$current_url" "$location")"
                redirect_count=$((redirect_count + 1))
                [[ "$redirect_count" -le "$MAX_REDIRECTS" ]] ||
                    fail "release asset download exceeded $MAX_REDIRECTS redirects"
                current_url="$next_url"
                ;;
            *)
                fail "release asset download returned unexpected HTTP status '$status'"
                ;;
        esac
    done
}

read_release_string() {
    local key_path="$1"
    local release_file="$2"
    local value

    if ! value="$(
        plutil -extract "$key_path" raw -expect string -o - "$release_file"
    )"; then
        fail "the GitLab Release response is missing string '$key_path'"
    fi
    printf '%s' "$value"
}

validate_release_assets() {
    local release_file="$1"
    local link_count
    local index
    local name
    local direct_path
    local package_url
    local link_type
    local expected_url
    local expected=0
    local expected_asset
    local seen_assets="|"

    if ! link_count="$(
        plutil -extract assets.links raw -expect array -o - "$release_file"
    )"; then
        fail "the GitLab Release response is missing the asset links array"
    fi
    [[ "$link_count" == "${#ASSETS[@]}" ]] ||
        fail "the GitLab Release must contain exactly ${#ASSETS[@]} asset links"

    index=0
    while [[ "$index" -lt "$link_count" ]]; do
        name="$(read_release_string "assets.links.$index.name" "$release_file")"
        direct_path="$(
            read_release_string "assets.links.$index.direct_asset_path" "$release_file"
        )"
        package_url="$(read_release_string "assets.links.$index.url" "$release_file")"
        link_type="$(read_release_string "assets.links.$index.link_type" "$release_file")"

        expected=0
        for expected_asset in "${ASSETS[@]}"; do
            if [[ "$name" == "$expected_asset" ]]; then
                expected=1
                break
            fi
        done
        [[ "$expected" -eq 1 ]] ||
            fail "the GitLab Release contains unexpected asset '$name'"
        [[ "$seen_assets" != *"|$name|"* ]] ||
            fail "the GitLab Release contains duplicate asset '$name'"
        seen_assets="$seen_assets$name|"

        [[ "$direct_path" == "/$name" ]] ||
            fail "published release asset '$name' has an unexpected direct path"
        expected_url="$CI_API_V4_URL/projects/$CI_PROJECT_ID/packages/generic/$PACKAGE_NAME/$CI_COMMIT_TAG/$name"
        [[ "$package_url" == "$expected_url" ]] ||
            fail "published release asset '$name' does not target the confirmed project package"
        [[ "$link_type" == "package" ]] ||
            fail "published release asset '$name' does not use package link type"

        index=$((index + 1))
    done
}

"$ROOT/scripts/gitlab-release-preflight.sh"

[[ -n "${CI_JOB_TOKEN:-}" ]] ||
    fail "CI_JOB_TOKEN is required to verify the published GitLab Release"
for command in cmp curl mktemp mv plutil shasum; do
    command -v "$command" >/dev/null 2>&1 ||
        fail "$command is required to verify the GitLab Release"
done

VERSIONED_DMG="ReluxProxy-$CI_COMMIT_TAG-universal.dmg"
ASSETS=(
    "$VERSIONED_DMG"
    "ReluxProxy.dmg"
    "SHA256SUMS"
)

rm -rf "$VERIFY_DIR"
mkdir -p "$VERIFY_DIR"
TEMP_ROOT="${TMPDIR:-/tmp}"
TEMP_ROOT="${TEMP_ROOT%/}"
REQUEST_TEMP="$(mktemp -d "$TEMP_ROOT/relux-release-verification.XXXXXX")"

RELEASE_API="$CI_API_V4_URL/projects/$CI_PROJECT_ID/releases/$CI_COMMIT_TAG"
fetch_release_metadata "$RELEASE_API" "$VERIFY_DIR/release.json"

published_tag="$(read_release_string tag_name "$VERIFY_DIR/release.json")"
published_commit="$(read_release_string commit.id "$VERIFY_DIR/release.json")"
[[ "$published_tag" == "$CI_COMMIT_TAG" ]] ||
    fail "the published release tag is '$published_tag', not '$CI_COMMIT_TAG'"
[[ "$published_commit" == "$CI_COMMIT_SHA" ]] ||
    fail "the published release points to '$published_commit', not the accepted commit"
validate_release_assets "$VERIFY_DIR/release.json"

DIRECT_DOWNLOAD_BASE="$CI_API_V4_URL/projects/$CI_PROJECT_ID/releases/$CI_COMMIT_TAG/downloads"
for asset in "${ASSETS[@]}"; do
    fetch_release_asset "$DIRECT_DOWNLOAD_BASE/$asset" "$VERIFY_DIR/$asset"
done

cmp -s "$DIST/SHA256SUMS" "$VERIFY_DIR/SHA256SUMS" ||
    fail "the published SHA256SUMS differs from the CI-produced checksum file"
(
    cd "$VERIFY_DIR"
    shasum -a 256 -c SHA256SUMS
)
cmp -s "$VERIFY_DIR/$VERSIONED_DMG" "$VERIFY_DIR/ReluxProxy.dmg" ||
    fail "the published stable-name DMG differs from the versioned DMG"

echo "Verified the GitLab Release, accepted commit, asset links, and published hashes"
