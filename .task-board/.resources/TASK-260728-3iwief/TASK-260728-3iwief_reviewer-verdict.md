# TASK-260728-3iwief reviewer verdict

Date: 2026-07-28
Role: reviewer
Branch: changes requested → `to-dev`

## Verdict

Changes requested. The protected-tag, accepted-SHA, signing, notarization,
Gatekeeper, upload, checksum, documentation, and local regression controls are
otherwise coherent and fail closed, but the post-publication download uses an
authentication/endpoint pairing that is not supported for private GitLab
permanent asset links.

This is ordinary implementation rework, not a stop-the-line boundary.

## Required change

### High — use the Releases API endpoint for job-token asset verification

`scripts/verify-gitlab-release.sh:49-58` builds the browser-style permanent
asset route:

```text
$CI_PROJECT_URL/-/releases/$CI_COMMIT_TAG/downloads/<asset>
```

and sends `JOB-TOKEN: $CI_JOB_TOKEN`.

GitLab documents personal-access-token authentication for private
browser-style permanent asset links. GitLab separately documents
`CI_JOB_TOKEN` support for the Releases API asset-download endpoint:

```text
GET /projects/:id/releases/:tag_name/downloads/:direct_asset_path
```

Evidence:

- https://docs.gitlab.com/user/project/releases/release_fields/#permanent-links-to-release-assets
- https://docs.gitlab.com/api/releases/#download-a-release-asset
- https://docs.gitlab.com/ci/jobs/fine_grained_permissions/#releases-endpoints

Impact: on a private Relux project, the release and package assets can be
created successfully and the subsequent verification job can then fail
authentication on the browser route. The target project is not yet confirmed,
so the implementation cannot safely assume public visibility.

Required rework:

1. Keep `JOB-TOKEN`, but download each direct asset through:

   ```text
   $CI_API_V4_URL/projects/$CI_PROJECT_ID/releases/$CI_COMMIT_TAG/downloads/<asset>
   ```

2. Add a regression that asserts the exact Releases API base and fails if the
   browser-style `/-/releases/` route is used with the job token.
3. Re-run the shell, Swift, app-build, preflight, upload, and verification
   matrices.

## Controls independently audited

- `.gitlab-ci.yml` creates only the exact `v0.2.0` tag release pipeline, rejects
  other tag pipelines, uses the `macos` and `relux-release` runner tags,
  serializes production through `relux-production-release`, and requires the
  production environment.
- `gitlab-release-preflight.sh` requires the confirmed host and case-sensitive
  project path, HTTPS project/API URLs, the exact tag, a pushed protected ref,
  full lowercase 40-character CI and accepted SHAs, equality between them,
  equality with checked-out `HEAD`, both runner tags, and the required release
  note content.
- `build-app.sh` rejects an ad-hoc production signature and a missing required
  identity. The release path imports into a disposable keychain, requires the
  exact Relux Works Developer ID and team, enables hardened runtime, and
  verifies a universal `arm64` + `x86_64` app.
- `release-macos.sh` requires an `Accepted` notary result and submission ID,
  retains the notarization log, staples and validates the DMG, re-verifies its
  signature, requires Gatekeeper success, copies the stable name only after
  those gates, proves byte equality, and generates then verifies both SHA-256
  entries.
- `upload-gitlab-release-assets.sh` requires a job token and all non-empty
  assets, validates checksums and byte equality before its first upload, and
  targets the confirmed project’s Generic Package Registry.
- `verify-gitlab-release.sh` correctly verifies the Release API tag and
  `commit.id`, checksum-file equality, downloaded hashes, and stable/versioned
  byte equality. Only its asset-download base requires rework.
- The runbook requires masked, hidden, protected secrets with expansion
  disabled, documents the exact project/runner/credential prerequisites, and
  does not claim that a GitLab v0.2.0 release already exists.
- No scoped script enables shell tracing or prints secret values. Decoded
  certificate/key files and the temporary keychain are confined to a
  `mktemp` directory and removed by an exit trap.

## Independent validation

All commands operated on an isolated current-worktree snapshot under
`.temp/TASK-260728-3iwief/review/sandbox`.

| Gate | Result |
| --- | --- |
| `shellcheck scripts/*.sh` | passed |
| `bash -n scripts/*.sh` | passed |
| local Ruby YAML parse and required-job check | passed |
| `swift format lint --recursive --strict Sources Tests` | passed |
| `swift test` | 49 tests in 8 suites passed |
| `swift build` | passed |
| ad-hoc `VERSION=v0.2.0 scripts/build-app.sh` | passed |
| built app architecture inspection | `x86_64 arm64` |
| built app version/signature inspection | `0.2.0`, build `20260728`, valid ad-hoc signature |
| preflight matrix | positive plus 11 expected-negative cases passed |
| signing guard matrix | 4 expected-negative cases passed |
| offline upload matrix | positive plus 4 expected-negative cases passed |
| offline verification matrix | positive plus 6 expected-negative cases passed |
| `git diff --check` and scoped trailing-whitespace scan | passed |

The preflight negatives covered excluded/wrong host, wrong project, wrong API
host, wrong tag, unprotected ref, wrong pipeline source, accepted-SHA mismatch,
checkout-SHA mismatch, missing runner tag, and missing accepted SHA.

The publication negatives covered missing tokens/assets, bad local checksums,
divergent local aliases, wrong published tag/SHA, changed checksum files,
corrupted downloads, and divergent published aliases.

The offline publication tests resolved `curl` to the task-scoped local stub and
used synthetic values. No GitLab repository, package, tag, release, notary, or
other external mutation was attempted.

The current checkout has no local `v0.2.0` tag and only the pre-existing GitHub
`origin`. A before/after content fingerprint of tracked diffs, staged diffs, and
untracked files outside `.task-board/` and `.temp/` was identical.

The harness used current `HEAD`
`7e6f25b81c158128197cdfa618644a003859c8fa` only to exercise checkout-equality
guards. It is not an assertion that this uncommitted worktree state is the
future accepted production release SHA.

## Deliberate scope boundary

No Developer ID key, App Store Connect credential, real notarization request,
real Gatekeeper-approved production candidate, or external GitLab target was
used. Apple CLI help and official Apple documentation confirmed the implemented
`notarytool submit --wait`, `notarytool log`, `stapler staple`, and
`stapler validate` contracts:

- https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
- https://developer.apple.com/developer-id/

