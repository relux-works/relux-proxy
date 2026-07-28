# TASK-260728-35ogr2 logbook

## Decisions

- Installed the relux-proxy runner in
  `/Users/administrator/actions-runner-relux-proxy-release` with its own
  LaunchAgent instead of sharing any tgfs files or service state.
- Kept the host-wide `xcode-select` on Command Line Tools. Full Xcode is
  selected only in the dedicated runner `.env` and release job through
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; changing the
  global selection could alter tgfs jobs.
- Restricted `.github/workflows/release.yml` to the exact `v0.2.0` tag and
  `[self-hosted, macOS, X64, relux-proxy-release]`.
- Kept the regular pull-request workflow on GitHub-hosted macOS. The privileged
  self-hosted label is release-only because the repository is public.
- Added a fail-closed preflight before credential decoding and an exact
  Developer ID check after keychain import.
- Used a unique temporary directory/keychain plus an `always()` cleanup step
  because this runner persists across jobs.

## Findings

- GitHub account `ivanopcode` has `ADMIN` on
  `relux-works/relux-proxy`.
- The configured Actions secret names are `ASC_ISSUER_ID`, `ASC_KEY_ID`,
  `ASC_KEY_P8`, and `MACOS_CERT_P12`. No value was queried.
- The Intel host runs macOS 15.7.4 and full Xcode 26.2. Its system
  `xcode-select` points to Command Line Tools.
- The existing `relux-works/tgfs` runner remained online and idle. Its runner
  metadata, credentials, RSA parameters, and LaunchAgent plist fingerprints
  were unchanged after configuration.
- GitHub Actions runner 2.336.0 was current at installation time. The official
  macOS x64 archive SHA-256 matched
  `f79c43232761ca495fc18df550bb2865aa99984b37c173c0aa1f8c09d0d548fe`.
- GitHub assigned the dedicated runner ID 21 and reports it online, idle, and
  labeled `self-hosted`, `macOS`, `X64`, `relux-proxy-release`.
- No `v0.2.0` tag or GitHub Release exists after this work.

## Anomalies and resolutions

- The first read-only remote probe exited 127 because `/usr/bin/test` is not a
  macOS executable path. The corrected probe used the shell builtin and passed;
  it had stopped before runner inspection or mutation.
- The first two targeted test runs exited 1 while the preflight contract was
  being made locally testable without weakening the remote Xcode gate. The
  final targeted suite and full suite pass.
- Initial `actionlint` exited 1 because the custom self-hosted runner label was
  unknown. `.github/actionlint.yaml` now declares the exact label, preserving
  label typo checking; the final lint passes.
- The task intentionally did not push the uncommitted workflow or manufacture a
  tag-triggered release job. Remote smoke evidence therefore consists of the
  running listener, exact GitHub online/idle labels, scoped full-Xcode command
  checks, and tgfs immutability verification.
- The worktree contained extensive unrelated changes before this task. None
  were staged, reverted, overwritten, or included in the task-scoped edits.

## Reviewer rework

- Review found that `set -e` in the original `always()` cleanup block stopped
  execution after a failed `security delete-keychain`, before
  `RELEASE_TEMP` removal. The reviewer reproduced exit 37 with the simulated
  keychain and `asc.p8` both retained.
- Cleanup now lives in `scripts/github-release-cleanup.sh`. It keeps the
  destructive-path guards, attempts safe keychain deletion and safe temp
  removal independently, and returns the first nonzero cleanup status.
- A Swift failure-path regression makes a fake `security` command exit 37 and
  verifies that the script still removes the keychain file, `asc.p8`, and
  release directory while returning 37.
- The regression was red before implementation (targeted tests exit 1) and
  green afterward (exit 0, 5 tests). The first rework lint run exited 2 on
  multiline-fixture indentation; after correction, lint and all remaining
  gates passed.
- The first credential-scan invocation exited 1 on a malformed shell quote
  before reading files. The corrected silent scan exited 0 across ten
  task-scoped source and evidence files without printing any matching content.
- Post-rework remote checks found runner ID 21 online and idle, both
  LaunchAgents healthy, full Xcode 26.2 selected for the dedicated runner, and
  every protected tgfs fingerprint unchanged.
- No runner configuration, tag, Release, push, or secret value changed during
  this rework.
