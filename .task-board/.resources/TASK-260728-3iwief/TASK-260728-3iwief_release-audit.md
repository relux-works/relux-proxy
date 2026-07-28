# TASK-260728-3iwief — v0.2.0 GitLab release automation rework audit

Date: 2026-07-28
Role: developer
Scope: repository-local validation only; no GitLab, package registry, tag,
release, notarization, or other external mutation.

## Rework applied

The prior reviewer correctly found that the verifier paired CI_JOB_TOKEN with
the browser-oriented /-/releases/ permanent-link route. The verifier now
downloads each asset through the job-token-supported Releases API endpoint:

~~~
$CI_API_V4_URL/projects/$CI_PROJECT_ID/releases/$CI_COMMIT_TAG/downloads/<asset>
~~~

The focused Swift regression requires that exact base and fails if
scripts/verify-gitlab-release.sh contains /-/releases/. The GitLab release
runbook now distinguishes end-user browser permanent links from the
authenticated CI API route.

## Independent control trace

- .gitlab-ci.yml permits the release/verification jobs only for tag v0.2.0,
  assigns both macos and relux-release, serializes production work, and retains
  the release/verification evidence artifacts.
- gitlab-release-preflight.sh requires the confirmed host and case-sensitive
  project, HTTPS/API ownership, pushed protected tag, full lowercase
  CI_COMMIT_SHA, exact accepted SHA, checked-out SHA equality, both runner
  tags, and required release-note content.
- release-macos.sh uses a disposable keychain, validates the exact Developer
  ID and team, requires hardened-runtime signing, Accepted notarization,
  notarization-log retrieval, stapling, stapler validation, Gatekeeper, alias
  byte equality, and checked SHA-256 output.
- Upload rejects missing job token, empty assets, checksum errors, and
  divergent aliases before its first upload. Verification rejects missing job
  token, wrong release tag/commit, changed checksums, corrupted downloads, and
  divergent aliases.

GitLab’s Releases API documents JOB-TOKEN authentication and the exact
GET /projects/:id/releases/:tag_name/downloads/:direct_asset_path route:
<https://docs.gitlab.com/api/releases/>. Apple’s notarization workflow confirms
notarytool --wait, log retrieval, stapling, and offline ticket validation:
<https://developer.apple.com/documentation/security/customizing-the-notarization-workflow>.

## Safe local validation

All commands below were executed directly. Positive gates exited 0.

| Gate | Result |
| --- | --- |
| shellcheck scripts/*.sh | exit 0 |
| bash -n scripts/*.sh | exit 0 |
| Ruby YAML parse plus required release/verify-job check | exit 0 |
| swift format lint --recursive --strict Sources Tests | exit 0 |
| swift test | exit 0; 49 tests in 8 suites |
| swift build | exit 0 |
| isolated ad-hoc app build | exit 0; universal x86_64 arm64, version 0.2.0, build 20260728, valid ad-hoc signature |
| preflight positive context | exit 0 |
| 12 preflight negatives | each exit 1 as expected: excluded/wrong host, wrong project/URL/API host, wrong tag, unprotected tag, wrong source, accepted-SHA mismatch, checkout-SHA mismatch, missing runner tag, and missing accepted SHA |
| production ad-hoc signature guard | exit 1 as expected |
| release script with preflight-only synthetic context but missing release variables | exit 1 as expected before credential decoding or external action |
| offline upload positive through local curl/git stubs | exit 0 |
| offline verification positive through local curl/git stubs | exit 0 |
| upload missing token, missing asset, and bad checksum | each exit 1 as expected |
| verification missing token, wrong published commit, and mismatched published checksum | each exit 1 as expected |

The local stub accepted only:

~~~
https://gitlab.relux.example/api/v4/projects/42/releases/v0.2.0
https://gitlab.relux.example/api/v4/projects/42/releases/v0.2.0/downloads/<asset>
~~~

It rejects browser /-/releases/ URLs and records no credential values.

## Safety evidence

- The local checkout still has only the expected GitHub origin URL check
  (exit 0) and no local v0.2.0 ref (git show-ref exit 1, expected).
- A browser-route scan of the verifier, tracing/printenv scan, and
  trailing-whitespace scan each exited 1 because they found no matches; these
  are expected-negative search results, not passing command statuses.
- One diagnostic checksum attempt from the repository root exited 1 because
  SHA256SUMS contains filenames relative to dist; the corrected checksum command
  executed in dist exited 0.
- xcrun stapler --help exited 64 because the tool requires the staple or
  validate subcommand; notarytool submit --help and notarytool log --help both
  exited 0 and matched the scripted contracts.
- Source changes from this run are limited to the verifier, its focused Swift
  regression, and the GitLab release runbook. Temporary stubs and logs are
  task-scoped under .temp/TASK-260728-3iwief/.

## Handoff

The required rework is implemented and independently validated. The reviewer
should now evaluate this new evidence and choose the normal accepted or
changes-requested verdict branch.
