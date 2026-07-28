# TASK-260728-3iwief reviewer verdict — RUN-260728-9253a8

Date: 2026-07-28
Role: reviewer
Branch: changes requested → `to-dev`
Run goal: none; the run is not goal-bound

## Verdict

Changes requested. The prior browser-route/job-token mismatch was correctly
reworked to the supported Releases API endpoint, and all requested repository-
local gates pass. The verifier still combines a sensitive custom `JOB-TOKEN`
header with automatic redirect following. That can disclose the running job
token before the later checksum gates execute.

This is ordinary implementation rework, not a stop-the-line boundary.

## Required change

### High — do not forward `JOB-TOKEN` across release-asset redirects

`scripts/verify-gitlab-release.sh:49-58` requests each Releases API direct-asset
URL with both:

```text
--location
--header "JOB-TOKEN: $CI_JOB_TOKEN"
```

GitLab documents that a release asset link can target an internal or external
URL and that the permanent/direct URL always redirects to the configured
location. curl documents that custom headers supplied with `--header` are sent
on redirected HTTP requests as well; only special headers such as
`Authorization` and `Cookie` receive cross-origin suppression.

A local reproduction used two loopback HTTP servers with different host spellings
and a synthetic token. The first server returned a redirect; the second server
received the synthetic `JOB-TOKEN`. No external request or real credential was
used.

Impact: a modified release link, or an as-yet-unknown self-managed GitLab/object
storage redirect policy, can receive the CI job token. Hash verification happens
after the download and therefore cannot prevent the disclosure. The same
`--location` plus custom job-token pattern in the upload helper should be
reviewed and hardened as part of the fix.

Required rework:

1. Never automatically follow a redirect while a custom `JOB-TOKEN` header is
   attached.
2. Validate the Release response contains exactly the expected asset names,
   direct paths, and same-project Generic Package Registry URLs.
3. Download through a redirect-safe helper: send the job token only to the
   confirmed GitLab origin; if GitLab returns an allowed HTTPS object-storage
   redirect, fetch that location without the job token. Fail closed on every
   other origin, scheme, status, missing header, or malformed response.
4. Harden upload redirects similarly, or reject redirects and require the exact
   successful package-upload status.
5. Add a regression with two local endpoints proving a synthetic `JOB-TOKEN`
   never reaches a redirected origin. Retain the exact Releases API route
   regression and rerun the existing matrices.

Primary contract evidence:

- GitLab Releases API authentication and direct-asset endpoint:
  https://docs.gitlab.com/api/releases/
- GitLab release links may be external and permanent links redirect:
  https://docs.gitlab.com/user/project/releases/release_fields/
- curl custom-header redirect warning:
  https://curl.se/docs/manpage.html#-H

## Controls independently audited

- `.gitlab-ci.yml` creates a release pipeline only for exact tag `v0.2.0`,
  rejects other tag pipelines, requires `macos` and `relux-release`, serializes
  the production release job, uses the protected production environment, and
  makes verification depend on the release job and its artifacts.
- `gitlab-release-preflight.sh` requires the confirmed non-excluded host,
  case-sensitive project, HTTPS project/API identity, exact tag, pushed
  protected ref, full lowercase CI and accepted SHAs, equality between those
  SHAs and checked-out `HEAD`, both runner tags, and required release notes.
- `build-app.sh` rejects invalid production-signing mode, an ad-hoc production
  identity, and a missing required identity. The production path selects the
  disposable keychain and hardened runtime.
- `release-macos.sh` requires the exact Relux Works Developer ID and team,
  universal architectures, a valid signature, an `Accepted` notary result and
  submission ID, notary-log retrieval, stapling, stapler validation, a second
  signature check, Gatekeeper success, alias byte equality, and generated plus
  verified SHA-256 entries before reporting success.
- `upload-gitlab-release-assets.sh` rejects a missing token, a missing/empty
  asset, checksum failure, and divergent aliases before its first upload.
- `verify-gitlab-release.sh` now uses the exact job-token-supported Releases API
  path and rejects a wrong Release tag/commit, changed checksum file, corrupt
  download, or divergent aliases. Redirect credential handling is the remaining
  defect.
- Release docs/spec accurately keep GitLab publication unclaimed and gated on
  the still-unknown Relux target, owner, protected runner, and credentials.

Apple's current notarization documentation and installed Xcode help match the
implemented `notarytool submit --wait`, result/log handling, `stapler staple`,
and `stapler validate` sequence:
https://developer.apple.com/documentation/security/customizing-the-notarization-workflow

## Independent local validation

All build/test commands ran in a fresh task-scoped snapshot under
`.temp/TASK-260728-3iwief/reviewer-RUN-260728-9253a8-Ft91W6/`.

| Gate | Result |
| --- | --- |
| Tool readiness | Xcode 26.5; Swift Format 6.3.0; ShellCheck 0.11.0; notarytool/stapler/codesign/spctl available |
| `shellcheck scripts/*.sh` | passed |
| per-file `/bin/bash -n` | all scripts passed |
| local Ruby YAML parse plus exact workflow/job assertions | passed |
| `swift format lint --recursive --strict Sources Tests` | passed |
| `swift test` | 49 tests in 8 suites passed |
| `swift build` | passed |
| isolated ad-hoc `v0.2.0` app build | passed |
| app inspection | universal `x86_64 arm64`; version `0.2.0`; build `20260728`; valid ad-hoc signature |
| preflight matrix | 1 positive + 16 expected negatives passed |
| signing guard matrix | 3 expected negatives passed |
| release entry guards | 2 expected negatives passed before decoding or external action |
| synthetic offline upload matrix | 1 positive + 4 expected negatives passed |
| synthetic offline verification matrix | 1 positive + 6 expected negatives passed |
| release signing/notary/staple/Gatekeeper/checksum ordering assertion | passed |
| `git diff --check` | passed |
| secret/tracing/artifact scans | passed |
| redirect credential reproduction | synthetic `JOB-TOKEN` reached the redirected origin |

The negative preflight cases covered the explicitly excluded host, wrong host,
case-sensitive project mismatch, non-HTTPS server URL, wrong project/API URLs,
wrong tag, unprotected ref, non-push source, malformed CI SHA, accepted-SHA
mismatch, checked-out-SHA mismatch, both missing runner tags, missing accepted
SHA, and missing project ID.

The publication negatives covered missing tokens/assets, corrupt local
checksums, divergent local aliases, wrong published tag/commit, changed
published checksum file, corrupt downloads, and divergent published aliases.

## Safety evidence and scope boundary

- Every publication request used an exported task-local curl stub; the redirect
  reproduction used loopback only.
- No GitLab remote was added. The repository still has only the expected GitHub
  `origin`, and no local `v0.2.0` tag exists.
- No real GitLab API/package/release request, push, tag, notarization submission,
  or credential use occurred.
- No scoped script enables shell tracing or dumps the environment. No literal
  private key or common token material was found. CI artifacts/evidence exclude
  decoded credentials and the temporary keychain.
- The before/after fingerprint of tracked diffs, staged diffs, and untracked
  files outside `.task-board/` and `.temp/` remained identical:
  `a74e60eccf41507a1c59345849d24bc5387df70345e4e3d92381bfbb84488fb9`.
- Real Developer ID signing, Apple notarization, ticket stapling, and Gatekeeper
  assessment remain deliberately unexecuted because no production credentials
  or candidate were authorized for this review.

