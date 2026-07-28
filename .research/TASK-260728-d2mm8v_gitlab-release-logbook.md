# TASK-260728-d2mm8v GitLab release logbook

Date: 2026-07-28
Role: developer

## Findings

- The checkout has only
  `git@github.com:relux-works/relux-proxy.git` as `origin`; no GitLab remote,
  project path, or project ID is configured.
- `glab auth status` returned exit 1. `gitlab.com` returned HTTP 401 with no
  token. Explicit SSH authentication probes for the local Relux bot and project
  identities both returned exit 255 (`Permission denied (publickey)`).
- A credential exists for `gitlab.wildberries.ru`, but that host is explicitly
  excluded by the task. It was not used for a repository, package, tag, or
  Release request.
- The login keychain contains
  `Developer ID Application: Relux Works, LLC (262RZ595FP)`. No CI certificate
  payload or App Store Connect notarization variable is present in the process
  environment.
- No remote mutation was made: no GitLab remote was added, and no push, mirror,
  tag, package upload, or Release request was attempted.

## Implementation decisions

- `.gitlab-ci.yml` separates ordinary validation from protected production
  release and post-publication verification jobs.
- Production requires exact matches between GitLab's predefined host/project
  values and protected `RELUX_GITLAB_HOST` /
  `RELUX_GITLAB_PROJECT_PATH` values. It explicitly rejects
  `gitlab.wildberries.ru`.
- `RELUX_ACCEPTED_RELEASE_SHA` must equal the full checked-out tag commit.
  `v0.2.0` must be protected and run from a pushed tag on a runner carrying
  both `macos` and `relux-release`.
- Apple secrets are supplied as masked, hidden, protected variables. The
  certificate and App Store Connect key are decoded under `mktemp`; signing
  uses a disposable keychain that is removed on every exit.
- The release script requires the exact Relux Works Developer ID, hardened
  runtime, `arm64` + `x86_64`, accepted notarization, the notarization log,
  stapling, Gatekeeper approval, stable/versioned byte equality, and valid
  checksums. Production mode cannot fall back to an ad-hoc signature.
- Assets are uploaded to the same project's GitLab Generic Package Registry
  with `CI_JOB_TOKEN`, then exposed as three Release links. The verification job
  re-downloads the Release links and compares the published hashes and commit.
- The legacy multi-tunnel specification now records v0.2.0 as shipped product
  behavior while explicitly avoiding a false claim that the GitLab Release has
  been published.

## Validation and anomalies

Successful gates:

| Command | Exit | Evidence |
| --- | ---: | --- |
| `shellcheck scripts/*.sh` | 0 | Release and packaging scripts lint cleanly. |
| `bash -n scripts/*.sh` | 0 | Shell syntax is valid. |
| `swift format lint --recursive --strict Sources Tests` | 0 | Swift source and tests satisfy formatting. |
| `swift test` | 0 | 49 tests in 8 suites passed, including new release automation tests. |
| `swift build` | 0 | Swift package builds. |
| ad-hoc universal `scripts/build-app.sh` | 0 | Development bundle builds and verifies. |
| Developer ID `scripts/build-app.sh` | 0 | Universal app signed by team `262RZ595FP` with hardened runtime. |
| `scripts/create-dmg.sh` | 0 | Local v0.2.0 universal DMG created. |
| DMG `codesign` and `codesign --verify` | 0 | Local DMG has a valid Developer ID signature. |
| corrected `lipo <binary> -verify_arch arm64 x86_64` | 0 | Both architectures are present. |
| local `shasum -a 256 -c SHA256SUMS` | 0 | Both local DMG names match the generated hash. |
| local YAML parse of `.gitlab-ci.yml` | 0 | YAML is syntactically valid. |
| `git diff --check` | 0 | No whitespace errors in tracked diffs. |

Two implementation defects were found and corrected during real gates:

1. The first `lipo -verify_arch arm64 x86_64 <binary>` attempt returned exit 1
   because Xcode requires the input before the operation. The release script
   and test now use `lipo <binary> -verify_arch arm64 x86_64`; the rerun exited
   0.
2. The first required-Developer-ID build returned exit 1 because macOS Bash 3.2
   treats an empty array expansion as unbound under `set -u`. Explicit
   keyed/unkeyed signing branches replaced the array; the rerun exited 0.

The local Gatekeeper command returned exit 3 with
`source=Unnotarized Developer ID`. This is an expected failing production gate:
the App Store Connect notarization credentials are absent, so the local signed
DMG is not a production artifact and was not published.

Local non-production checksum observed after signing but before notarization:

```text
e5f1b16a82d3e5139d20e472ae4ce49bb5e2ad4d1897b060f68591d7a9a665b1  ReluxProxy-v0.2.0-universal.dmg
e5f1b16a82d3e5139d20e472ae4ce49bb5e2ad4d1897b060f68591d7a9a665b1  ReluxProxy.dmg
```

These hashes must not be represented as published hashes because notarization
and stapling would modify the production DMG.

## External blocker packet

Constraint: acceptance requires a production mutation on the exact Relux
GitLab project plus a protected macOS runner and notarization credentials.
Neither the project identity nor authorization/runner/credentials are supplied
in this run.

Failed assumptions/attempts: the repository remote and board metadata did not
name a GitLab target; `gitlab.com` API and SSH authorization were unavailable.
The only authenticated alternate GitLab host is explicitly prohibited.

Viable options:

1. **Recommended:** a Relux owner supplies and records the exact hostname,
   namespace/project, project ID, authorized release account, accepted commit
   SHA, protected project runner, protected production environment, and masked
   signing/notarization variables. Then mirror the accepted commit, push the
   signed `v0.2.0` tag, and retain both successful production jobs.
2. Continue publishing only on GitHub. This preserves the existing channel but
   does not satisfy the assigned GitLab acceptance criteria.
3. Use `gitlab.wildberries.ru`. This is prohibited, unrelated, and must not be
   considered.

Exact input needed to resume: confirmation of
`<GitLab hostname>/<namespace>/<repository>` and project ID, proof that the
release operator can push and create packages/releases there, the accepted
40-character commit SHA, a protected `macos` + `relux-release` runner, and the
seven protected release variables listed in `docs/gitlab-release.md`.
