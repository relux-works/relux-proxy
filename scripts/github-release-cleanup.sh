#!/bin/bash
set -uo pipefail

cleanup_status=0
release_temp_is_safe=0
runner_temp="${RUNNER_TEMP:-}"
release_temp="${RELEASE_TEMP:-}"
release_keychain="${RELEASE_KEYCHAIN:-}"

if [[ -n "$release_temp" ]]; then
    if [[ -z "$runner_temp" ]]; then
        echo "error: refusing release cleanup without RUNNER_TEMP" >&2
        cleanup_status=1
    else
        case "$release_temp" in
        "$runner_temp"/relux-release.*)
            release_temp_is_safe=1
            ;;
        *)
            echo "error: refusing to remove an unexpected release temp directory" >&2
            cleanup_status=1
            ;;
        esac
    fi
fi

if [[ -n "$release_keychain" ]]; then
    if [[ "$release_temp_is_safe" -ne 1 || "$release_keychain" != "$release_temp/"* ]]; then
        echo "error: refusing to remove a keychain outside the release temp directory" >&2
        cleanup_status=1
    elif [[ -e "$release_keychain" ]]; then
        if security delete-keychain "$release_keychain"; then
            :
        else
            operation_status=$?
            echo "error: failed to delete release keychain" >&2
            if [[ "$cleanup_status" -eq 0 ]]; then
                cleanup_status=$operation_status
            fi
        fi
    fi
fi

if [[ "$release_temp_is_safe" -eq 1 ]]; then
    if /bin/rm -rf -- "$release_temp"; then
        :
    else
        operation_status=$?
        echo "error: failed to remove release temp directory" >&2
        if [[ "$cleanup_status" -eq 0 ]]; then
            cleanup_status=$operation_status
        fi
    fi
fi

exit "$cleanup_status"
