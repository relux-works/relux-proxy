# TASK-260728-35ogr2 runner evidence

All observations in this artifact are sanitized. Secret values, GitHub
registration tokens, runner credential contents, private keys, and certificate
payloads are intentionally excluded.

## Preflight

Captured at 2026-07-28T17:42:39Z locally and 2026-07-28T17:42:41Z on the
runner host.

### Tool readiness

- `task-board`: 0.23.0
- `git`: 2.50.1
- `gh`: 2.83.2
- `ssh`: OpenSSH 10.2p1
- local Swift: 6.3.2
- `shellcheck`: 0.11.0
- `actionlint`: 1.7.12

### GitHub repository access

- Authenticated GitHub account: `ivanopcode`
- Repository: `relux-works/relux-proxy`
- Permission: `ADMIN`
- Default branch: `main`
- Actions secret names present: `ASC_ISSUER_ID`, `ASC_KEY_ID`,
  `ASC_KEY_P8`, `MACOS_CERT_P12`
- Dedicated repository runners before registration: none
- Existing `relux-works/tgfs` runner: `relux-gramdrive`, online, idle, labels
  `self-hosted`, `macOS`, `X64`, `gramdrive-mac`

No secret value was requested or displayed.

### Remote host and existing tgfs runner

- SSH alias: `relux`
- Account: `administrator`
- Architecture: `x86_64`
- macOS: 15.7.4
- System `xcode-select` before this task: Command Line Tools
- Full Xcode available at `/Applications/Xcode.app`: Xcode 26.2
- Remote Swift: 6.2.3, `x86_64-apple-macosx15.0`
- Existing runner directory: `/Users/administrator/actions-runner`
- Dedicated directory `/Users/administrator/actions-runner-relux-proxy-release`
  did not exist
- Existing service:
  `actions.runner.relux-works-tgfs.relux-gramdrive`
- Existing service state: PID 17646, `LastExitStatus = 0`

Immutable-file fingerprints captured before configuration:

| Existing tgfs file | SHA-256 |
| --- | --- |
| `.runner` | `fd5da77365e6fd0e43a66ee73234a3594900acd457ec6beafd454cdaacb1d44e` |
| `.credentials` | `820af1ec849be769c6450ab127be07b290774694cfa09d72ae2da3c0cb15ddb4` |
| `.credentials_rsaparams` | `961525fa11a9cf867f14c4dd614457a7d7658460b7b5fb80e8b2c81d0629244f` |
| LaunchAgent plist | `67d073f1985ce76da2015cc91cf008b60e1bf71a8e4037083c1214a80d5b01d9` |

The first combined host probe exited 127 because it referenced the nonexistent
macOS path `/usr/bin/test`. It stopped before runner inspection. The corrected
read-only probe used the shell `test` builtin and exited 0.

## Configuration

- Installed GitHub Actions runner 2.336.0 from the official
  `actions/runner` macOS x64 release.
- Verified the downloaded archive against GitHub's published SHA-256:
  `f79c43232761ca495fc18df550bb2865aa99984b37c173c0aa1f8c09d0d548fe`.
- Installed into the new directory
  `/Users/administrator/actions-runner-relux-proxy-release`.
- Registered repository runner `relux-proxy-release` with the custom
  `relux-proxy-release` label. GitHub supplied the standard `self-hosted`,
  `macOS`, and `X64` labels.
- Installed and started the separate LaunchAgent
  `actions.runner.relux-works-relux-proxy.relux-proxy-release`.
- Set only the dedicated runner's `.env` to
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The host-wide
  `xcode-select` value was not changed.
- The GitHub registration token traveled directly from the GitHub CLI process
  to `config.sh` over SSH standard input. It was not interpolated into the
  command, printed, saved to a file, copied into this artifact, or added to the
  repository.
- No source branch or tag was pushed, and no Release was created.

## Postflight

Captured at 2026-07-28T17:59:21Z locally and 2026-07-28T17:59:23Z on the
runner host.

- GitHub runner ID: 21
- Runner: `relux-proxy-release`
- OS: `macOS`
- Status: `online`
- Busy: `false`
- Labels: `self-hosted`, `macOS`, `X64`, `relux-proxy-release`
- Dedicated LaunchAgent: running with `LastExitStatus = 0`
- Dedicated runner version: 2.336.0
- Explicit toolchain smoke: Xcode 26.2, Swift 6.2.3, x86_64 target
- `v0.2.0` GitHub tag count: 0
- `v0.2.0` GitHub Release count: 0

The existing tgfs LaunchAgent remained running. Its protected fingerprints
after configuration exactly match preflight:

| Existing tgfs file | Preflight SHA-256 | Postflight |
| --- | --- | --- |
| `.runner` | `fd5da77365e6fd0e43a66ee73234a3594900acd457ec6beafd454cdaacb1d44e` | unchanged |
| `.credentials` | `820af1ec849be769c6450ab127be07b290774694cfa09d72ae2da3c0cb15ddb4` | unchanged |
| `.credentials_rsaparams` | `961525fa11a9cf867f14c4dd614457a7d7658460b7b5fb80e8b2c81d0629244f` | unchanged |
| LaunchAgent plist | `67d073f1985ce76da2015cc91cf008b60e1bf71a8e4037083c1214a80d5b01d9` | unchanged |

## Validation

Every final gate below ran as its own process. Exit codes are the actual process
results.

| Command or gate | Exit | Result |
| --- | ---: | --- |
| `swift test --filter GitHubReleaseAutomationTests` (initial) | 1 | Expected development red: local host lacked the remote Xcode path and one keychain assertion used the wrong variable spelling. |
| `swift test --filter GitHubReleaseAutomationTests` (second) | 1 | Expected development red: `DEVELOPER_DIR` affected the local macOS git shim. |
| `swift test --filter GitHubReleaseAutomationTests` (final) | 0 | 4 GitHub release contract/preflight tests passed. |
| `actionlint .github/workflows/*.yml` (initial) | 1 | Expected development red: custom runner label was not declared to actionlint. |
| `actionlint .github/workflows/*.yml` (final) | 0 | Both GitHub workflows validated. |
| `shellcheck scripts/*.sh` | 0 | All shell automation linted cleanly. |
| `make lint` | 0 | Strict Swift formatting lint passed. |
| `make test` | 0 | 55 tests in 10 suites passed. |
| `make build` | 0 | Swift debug build passed. |
| `git diff --check` | 0 | Task source diff has no whitespace errors. |
| Dedicated remote runner/Xcode smoke | 0 | Runner 2.336.0, full Xcode 26.2, Swift 6.2.3 x86_64, both LaunchAgents running. |
| GitHub online/idle and exact-label assertion | 0 | Exactly one matching dedicated runner. |
| tgfs fingerprint immutability assertion | 0 | Service running and all protected hashes unchanged. |
| Task-scoped token/private-key/encoded-secret scan | 0 | No matching payload in changed repository files or this outcome. |
| GitHub v0.2.0 tag/Release absence assertion | 0 | Tag count 0; Release count 0. |

The workflow now:

- targets `[self-hosted, macOS, X64, relux-proxy-release]` only;
- selects `/Applications/Xcode.app/Contents/Developer`;
- accepts only the exact `v0.2.0` tag and matching checkout;
- fails before credential decoding for a missing/wrong repository, runner,
  architecture, tag, SHA, full-Xcode selection, secret, or release identity;
- verifies the imported Relux Works Developer ID and forbids ad-hoc fallback;
- uses a task-local temporary keychain and removes credentials in an
  `always()` cleanup step on the persistent runner.

## Reviewer rework

Captured on 2026-07-28 after the first reviewer requested changes.

The reviewer reproduced a cleanup failure in which
`security delete-keychain` exited 37 and the inline `set -e` block skipped
removal of `RELEASE_TEMP`. That could retain the temporary keychain file and
decoded `asc.p8` on the persistent runner.

The rework:

- moves the guarded cleanup into `scripts/github-release-cleanup.sh`;
- validates that `RELEASE_TEMP` is below the runner temp directory and that
  `RELEASE_KEYCHAIN` is below that validated release directory;
- attempts keychain deletion and temp-directory removal independently;
- preserves the first nonzero operation status after all safe cleanup attempts;
- adds an executable Swift regression fixture in
  `GitHubReleaseAutomationTests` that makes `security` exit 37, confirms the
  command was invoked, confirms the script returns 37, and confirms the
  temporary keychain, decoded notarization key, and release directory are all
  absent afterward;
- documents the independent cleanup behavior in the GitHub release runbook.

### Rework validation

Every gate below ran as its own process. Exit codes are the actual process
results.

| Command or gate | Exit | Result |
| --- | ---: | --- |
| `swift test --filter GitHubReleaseAutomationTests` before implementation | 1 | Expected development red: the new regression found no cleanup script or workflow invocation, and the synthetic secret-bearing files remained. |
| `swift test --filter GitHubReleaseAutomationTests` after implementation | 0 | 5 GitHub release tests passed, including the exit-37 cleanup regression. |
| `shellcheck scripts/github-release-cleanup.sh` | 0 | New cleanup script linted cleanly. |
| First rework `make lint` | 2 | Failed truthfully on four multiline-fixture indentation diagnostics; the fixture was corrected. |
| Final `make lint` | 0 | Strict Swift formatting lint passed. |
| Final `make test` | 0 | 56 tests in 10 suites passed. |
| `shellcheck scripts/*.sh` | 0 | All shell automation linted cleanly. |
| `actionlint .github/workflows/*.yml` | 0 | Both GitHub workflows validated. |
| `make build` | 0 | Swift debug build passed. |
| `git diff --check` | 0 | The worktree diff has no whitespace errors. |
| GitHub repository access check | 0 | `relux-works/relux-proxy`, `ADMIN`, default branch `main`. |
| Required secret-name assertion | 0 | Exactly the four required names were present; values were not queried. |
| GitHub runner-state assertion | 0 | Runner ID 21 remained online and idle with the exact four required labels. |
| Dedicated remote runner/Xcode smoke | 0 | Runner 2.336.0, Xcode 26.2, Swift 6.2.3 x86_64, and both LaunchAgents healthy. |
| tgfs fingerprint assertion | 0 | All four protected fingerprints remained unchanged. |
| GitHub v0.2.0 tag/Release absence assertion | 0 | Local tag count, GitHub tag count, and GitHub Release count remained zero. |
| First task-scoped credential-payload scan invocation | 1 | The shell rejected a malformed quote in the literal-token regex before scanning or printing file content. |
| Final task-scoped credential-payload scan | 0 | Ten task source/evidence files contained no private-key/certificate header, GitHub token format, long encoded payload, serialized token response, or literal registration-token argument. |

No tag, Release, workflow run, runner reconfiguration, service restart, or
secret-value query was performed during rework. Registration tokens,
credentials, private keys, certificate payloads, and secret values are excluded
from this artifact.
