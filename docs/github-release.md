# GitHub macOS release runbook

GitHub Releases is the production publication target for Relux Proxy v0.2.0.
The dedicated runner is configured and healthy, but this runner-configuration
task does not create the `v0.2.0` tag or publish a GitHub Release.

## Dedicated runner boundary

The repository runner is intentionally isolated from the existing
`relux-works/tgfs` runner on the same Intel Mac:

| Property | relux-proxy release runner |
| --- | --- |
| Repository | `relux-works/relux-proxy` |
| Runner name | `relux-proxy-release` |
| Labels | `self-hosted`, `macOS`, `X64`, `relux-proxy-release` |
| Directory | `/Users/administrator/actions-runner-relux-proxy-release` |
| Work directory | `/Users/administrator/actions-runner-relux-proxy-release/_work` |
| LaunchAgent | `actions.runner.relux-works-relux-proxy.relux-proxy-release` |
| Full Xcode | `/Applications/Xcode.app/Contents/Developer` |

The pre-existing tgfs runner remains in
`/Users/administrator/actions-runner` under
`actions.runner.relux-works-tgfs.relux-gramdrive`. Never reuse, stop,
reconfigure, remove, or relabel that service while maintaining relux-proxy.

The dedicated runner stores `DEVELOPER_DIR` in its private `.env`, and
`.github/workflows/release.yml` sets the same value at job scope. The host's
system-wide `xcode-select` remains unchanged so this setup cannot alter tgfs
jobs.

As of 2026-07-28, GitHub reports `relux-proxy-release` online and idle. Check
the sanitized API state without requesting any credential value:

```bash
gh api repos/relux-works/relux-proxy/actions/runners \
  --jq '.runners[] | {
    name,
    os,
    status,
    busy,
    labels: [.labels[].name]
  }'
```

Check both LaunchAgents without changing either service:

```bash
ssh relux \
  'launchctl list actions.runner.relux-works-relux-proxy.relux-proxy-release'
ssh relux \
  'launchctl list actions.runner.relux-works-tgfs.relux-gramdrive'
```

The release label is privileged and must not be used by pull-request workflows.
The ordinary PR workflow continues to use a GitHub-hosted runner, so untrusted
fork code cannot request this persistent machine.

## Repository credentials

The following GitHub Actions secrets are configured by name:

| Secret | Purpose |
| --- | --- |
| `MACOS_CERT_P12` | Base64-encoded Relux Works Developer ID certificate and private key. |
| `ASC_KEY_ID` | App Store Connect API key ID. |
| `ASC_ISSUER_ID` | App Store Connect issuer ID. |
| `ASC_KEY_P8` | Base64-encoded App Store Connect private key. |

Never print, copy into evidence, persist outside GitHub Actions, or query the
values. A runner registration token is also one-time sensitive material: pass
it directly to `config.sh`, never save it to a file or command log, and let it
expire after registration.

The release job decodes credentials only into a unique directory below
`RUNNER_TEMP`, imports the certificate into a unique temporary keychain, and
deletes both in an `always()` cleanup step. Keychain deletion and temp-directory
removal are attempted independently, so a keychain command failure cannot skip
removal of decoded App Store Connect material; any cleanup failure still fails
the step. The persistent runner must not keep decoded certificates, App Store
Connect keys, or release keychains between jobs.

## Fail-closed workflow

`.github/workflows/release.yml` runs only for an exact `v0.2.0` tag push and
requires all four runner labels. `scripts/github-release-preflight.sh` stops
before credential decoding unless all of these are true:

- the event is a tag push for `relux-works/relux-proxy`;
- the tag is exactly `v0.2.0` and the checkout matches `GITHUB_SHA`;
- the runner is named `relux-proxy-release`, reports macOS and X64, and selects
  the full Xcode installation;
- all four Actions secrets are non-empty;
- the signing identity is exactly
  `Developer ID Application: Relux Works, LLC (262RZ595FP)`.

After import, the workflow checks that the temporary keychain actually contains
that Developer ID. Production mode sets `REQUIRE_DEVELOPER_ID=1`, passes the
temporary keychain explicitly to the build, and cannot fall back to an ad-hoc
signature. Notarization must return `Accepted`; stapling, `codesign`,
Gatekeeper, and checksum verification must all pass before publication.

The job publishes exactly:

- `ReluxProxy-v0.2.0-universal.dmg`
- `ReluxProxy.dmg`
- `SHA256SUMS`

## Validation and smoke check

Before tag creation, run:

```bash
make test
make lint
shellcheck scripts/*.sh
actionlint .github/workflows/*.yml
```

Verify the remote toolchain under the same explicit Xcode selection:

```bash
ssh relux '
  set -eu
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  /usr/bin/xcrun --find xcodebuild
  /usr/bin/xcodebuild -version
  /usr/bin/swift --version
  /bin/launchctl list \
    actions.runner.relux-works-relux-proxy.relux-proxy-release
'
```

A smoke check passes only when the commands above succeed and the repository
API reports the runner `online` with `busy: false` and the exact four labels.
Because this task does not push workflow changes or create the release tag, it
must not manufacture a release job merely to obtain smoke evidence.

## Release authorization

Creating or pushing `v0.2.0` is a separate, explicitly authorized release
operation. Before that operation, review and accept the exact commit, confirm
the workflow diff is on the default branch, repeat the health and validation
checks, and confirm the GitHub secret names still exist. Do not bypass a failed
preflight by broadening labels, changing the runner name, weakening identity
checks, or using the tgfs runner.

After the authorized tag workflow succeeds, verify the GitHub Release commit,
the three asset names, the provenance attestation, both SHA-256 entries, the
stapled ticket, and Gatekeeper acceptance before advertising v0.2.0.
