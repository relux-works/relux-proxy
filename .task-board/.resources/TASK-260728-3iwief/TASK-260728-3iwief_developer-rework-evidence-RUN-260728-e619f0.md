# TASK-260728-3iwief developer rework evidence — RUN-260728-e619f0

Date: 2026-07-28
Role: developer
Handoff target: fresh review
Scope: repository-local implementation and validation only

## Rework implemented

### Redirect credential isolation

`scripts/verify-gitlab-release.sh` no longer combines `JOB-TOKEN` with
automatic redirect following.

- Every curl invocation disables user curl configuration, permits HTTPS only,
  and sets the automatic redirect limit to zero.
- A manual redirect loop accepts only 301, 302, 303, 307, and 308; permits at
  most five hops; requires exactly one non-empty `Location`; and rejects
  whitespace/control characters, fragments, backslashes, scheme-relative URLs,
  non-HTTPS schemes, relative-path ambiguity, malformed URLs, and unexpected
  status codes.
- The exact origin is recomputed for every request. `JOB-TOKEN` is added only
  when that origin is byte-equal to the confirmed `CI_SERVER_URL`. External
  HTTPS object-storage hops are fetched without the header.
- Temporary response headers and bodies live in a `mktemp` directory removed
  by an exit trap, so signed redirect URLs are not retained as CI artifacts.
- The initial Release API and direct-download URLs must be on the confirmed
  GitLab origin.

Before downloading assets, the verifier now requires exactly three Release
links with the expected names, direct paths, `package` link type, and exact
same-project Generic Package Registry URLs. It retains the existing exact
release tag/commit check, checksum-file byte identity, per-file SHA-256
verification, and stable/versioned DMG byte equality.

`scripts/upload-gitlab-release-assets.sh` also disables curl configuration,
permits HTTPS only, does not follow redirects, and requires the Generic Package
Registry's exact HTTP 201 result.

### Exact project-ID binding

- `scripts/gitlab-release-preflight.sh` requires both `CI_PROJECT_ID` and the
  protected `RELUX_GITLAB_PROJECT_ID` to be positive numeric IDs and byte-equal.
- Both production GitLab CI jobs explicitly require the protected value and
  equality before their release scripts run.
- Package, Release, and download URLs remain constructed only after preflight.
- The runbook documents the protected variable, exact comparison, and
  fail-closed behavior.
- `RELEASE-EVIDENCE.txt` now records `gitlab_project_id`.

### Regression coverage

`GitLabReleaseRedirectTests` starts two real TLS loopback origins with an
ephemeral test certificate and a synthetic marker token.

- The confirmed GitLab origin rejects requests lacking the marker, proving
  authentication survives a same-origin hop.
- The second origin records whether `JOB-TOKEN` arrived and rejects a leak.
- A positive run downloads one asset after a same-origin redirect and two after
  cross-origin redirects; the second origin receives no job-token header.
- Expected-negative cases cover HTTP redirect, missing `Location`, malformed
  relative `Location`, more than five redirects, unexpected status, and a
  package URL outside the confirmed project.

The focused preflight regression also covers missing and mismatched protected
project IDs. Static production-script tests require redirect rejection and the
exact upload status, and assert the notarization/stapling/Gatekeeper/checksum
sequence.

## Current-source snapshot

Validation ran in:

`/Users/iv/Developer/relux-proxy/.temp/TASK-260728-3iwief/developer-RUN-260728-e619f0-current-snapshot`

The snapshot contains all current `Package.swift`, `Sources`, `Tests`,
`Resources`, `scripts`, `.gitlab-ci.yml`, `.github`, `Makefile`, `README.md`,
`docs`, `.spec`, and `release-notes` content. A final dry rsync comparison
returned exit 0 with zero output.

## Validation evidence

| Gate | Real result |
| --- | --- |
| `shellcheck scripts/*.sh` | exit 0 |
| Per-file `/bin/bash -n` | exit 0; 6 scripts |
| Ruby YAML parse and protected release-job assertions | exit 0; 3 YAML files |
| `swift format lint --recursive --strict Sources Tests` | exit 0 |
| `swift test` after the last source change | exit 0; 51 tests in 9 suites |
| `swift build` after the last source change | exit 0 |
| Universal ad-hoc app build | exit 0 |
| App architecture inspection | exit 0; `x86_64 arm64` |
| App version/build inspection | exit 0; `0.2.0` / `20260728` |
| Ad-hoc `codesign --verify --deep --strict` | exit 0 |
| Protected preflight matrix | exit 0 overall; 1 positive exit 0 + 20 expected failures, each exit 1 |
| Offline upload matrix | exit 0 overall; 1 positive exit 0 + 5 expected failures, each exit 1 |
| Offline verification matrix | exit 0 overall; 1 positive exit 0 + 7 expected failures, each exit 1 |
| Release entry/signing guard matrix | exit 0 overall; 5 expected failures, each exit 1 |
| Final source-snapshot parity | exit 0; zero differences |
| Final non-board worktree fingerprint comparison | exit 0; identical SHA-256 `abc6197570f32d14a7d3228e1f9c96f8056c876ea4510467fd9f4a68f859006d` |
| `git diff --check` | exit 0 |

The preflight negatives cover excluded/wrong host, wrong project path,
missing/malformed/mismatched project IDs, non-HTTPS identity, wrong project/API
URLs, wrong tag, unprotected ref, non-push source, malformed/missing/mismatched
SHAs, checkout mismatch, and each missing runner tag.

Publication negatives cover missing tokens/assets, bad local checksum,
divergent local aliases, upload redirect status, wrong Release tag/commit,
wrong-project link metadata, changed published checksum file, corrupt download,
and divergent published aliases.

The release guard negatives cover invalid signing mode, production ad-hoc
identity, absent required identity, missing release variables, and wrong
Developer ID. They fail before any authorized release action.

## Expected-red and corrected validation attempts

These results are retained rather than represented as passes:

- The first Bash-syntax wrapper launch returned exit 126 because the temporary
  wrapper was not executable. Running the same wrapper through `/bin/bash`
  returned exit 0 and checked all six scripts.
- The first offline matrix returned exit 126 after the upload cases because
  `verify-gitlab-release.sh` had lost its executable bit during replacement.
  The repository mode was corrected to 0755 and all four release scripts now
  pass `test -x`.
- The second offline matrix returned exit 1 because its exported curl fixture
  omitted one synthetic asset-name environment variable. The fixture was
  corrected; the third run returned exit 0 with the full upload/verification
  matrix above.
- `xcrun stapler --help` returned exit 64 and `spctl --help` returned exit 2
  because those CLIs treat bare help as usage errors. `notarytool submit
  --help` and `notarytool log --help` each returned exit 0. No notarization,
  stapling, or Gatekeeper release assessment was attempted.
- `git show-ref --verify refs/tags/v0.2.0` returned exit 128 for the absent ref;
  `git rev-parse --verify --quiet refs/tags/v0.2.0` independently returned
  exit 1, also confirming that no local release tag exists.
- Secret-pattern, shell-tracing, and trailing-whitespace `rg` scans each
  returned exit 1 because they found no matches.

## Safety and scope evidence

- The integration regression contacted only `127.0.0.1` TLS listeners and set
  both `NO_PROXY` spellings. The offline publication matrix replaced curl with
  an exported local function that accepted only the exact synthetic API URLs.
- No GitLab API, package registry, Release, upload, tag, push, or other external
  release endpoint was contacted.
- No Apple notarization submission, staple operation, or production Gatekeeper
  assessment was run.
- The only configured remote is
  `git@github.com:relux-works/relux-proxy.git` for fetch and push. No GitLab
  remote was added.
- No local `v0.2.0` tag exists.
- No real credential was used. Secret-pattern and tracing scans had no matches;
  temporary redirect headers are removed and are not archived.
- The validation commands changed only the task-scoped `.temp` snapshot.
  Current unrelated worktree content outside `.task-board` and `.temp` had the
  identical pre/post fingerprint shown above.
- No file was staged or committed, and nothing was pushed.

Logs are under
`/Users/iv/Developer/relux-proxy/.temp/TASK-260728-3iwief/validation-logs/`.

## Handoff

The redirect credential-safety and exact protected project-ID rework is ready
for a fresh reviewer verdict. Production publication remains intentionally
fail-closed until the Relux-owned GitLab target, protected variables, runner,
reviewed accepted SHA, and Apple credentials are supplied.
