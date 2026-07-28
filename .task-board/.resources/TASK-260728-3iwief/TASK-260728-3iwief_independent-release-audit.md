# Independent v0.2.0 GitLab release automation audit

Audit date: 2026-07-28  
Audited Git HEAD: `7e6f25b81c158128197cdfa618644a003859c8fa`  
Scope: repository-local files and safe localhost/isolated-worktree validation only. No GitLab, package registry, Apple notary service, tag, upload, or release mutation was attempted.

## Verdict: CHANGES REQUESTED

The current working-tree implementation has several solid fail-closed controls, but it is not eligible for a release handoff because two blocking conditions remain.

### Blocking finding 1 — release automation is not in the accepted Git tree

`git ls-tree -r HEAD` contains only `docs/current-state.md`, `scripts/build-app.sh`, and `scripts/create-dmg.sh` from the scoped set. The following required release files are untracked in the current checkout:

- `.gitlab-ci.yml`
- `scripts/gitlab-release-preflight.sh`
- `scripts/release-macos.sh`
- `scripts/upload-gitlab-release-assets.sh`
- `scripts/verify-gitlab-release.sh`
- `Tests/ReluxProxyTests/GitLabReleaseAutomationTests.swift`
- `docs/gitlab-release.md`
- `release-notes/v0.2.0.md`
- `.spec/legacy-socks-multi-tunnel.md`

Consequently, the accepted SHA cannot contain the pipeline, release scripts, release test, runbook, or release notes being audited. A protected v0.2.0 tag at this SHA cannot execute this automation.

Required rework: add the scoped release files to a reviewed commit, verify that the exact accepted SHA contains them, then re-run the audit before any remote operation.

### Blocking finding 2 — `CI_JOB_TOKEN` is forwarded across redirects

Both `scripts/upload-gitlab-release-assets.sh` (lines 40-47) and `scripts/verify-gitlab-release.sh` (lines 33-40 and 51-58) combine `curl --location` with a custom `--header "JOB-TOKEN: $CI_JOB_TOKEN"`.

The curl manual explicitly warns that headers supplied by `--header` are sent on all HTTP requests after redirects and may reach another host: <https://curl.se/docs/manpage.html>. A localhost-only probe using the exact option pattern and the synthetic value `audit-token-not-secret` returned `redirect_receiver_received_job_token=true` (probe command exit 0).

This is a runtime secret-exposure path despite the absence of hard-coded secret literals. It applies to the package upload and to release metadata/download requests.

Required rework: redesign redirects so the job token is sent only to the validated GitLab API origin, never to a followed location. Add a local redirect regression test with a synthetic token and assert that the redirect target receives no `JOB-TOKEN` header. Do not address this with a host allowlist alone unless the product owner accepts every storage redirect origin and its operational tradeoffs.

### Required hardening — independently bind the recorded project ID

The preflight requires a nonempty `CI_PROJECT_ID` but only compares the project path with `RELUX_GITLAB_PROJECT_PATH` (`scripts/gitlab-release-preflight.sh` lines 33-64). No `RELUX_GITLAB_PROJECT_ID` guard exists. The runbook identifies the project ID as a required target identity, so add a protected expected project-ID variable and require equality before construction of upload/release URLs.

## Controls that are present in the working-tree implementation

- `.gitlab-ci.yml` constrains the release and verify jobs to `v0.2.0`, uses `macos` plus `relux-release` tags, serializes production work, and retains release/verification evidence.
- Preflight rejects the explicitly excluded GitLab host, checks expected host/project path, HTTPS API origin, exact tag, pushed protected ref, full lowercase SHA, equality with `RELUX_ACCEPTED_RELEASE_SHA`, checkout SHA, and both runner tags.
- Production signing rejects ad-hoc release signing, requires the exact Developer ID and team, uses a temporary keychain, checks universal architectures, validates codesign, requires `notarytool` status `Accepted`, staples and validates the DMG ticket, runs Gatekeeper, and writes checksums/evidence.
- Upload checks every required artifact, validates `SHA256SUMS`, and asserts identical stable/versioned DMGs before curl. Verification anchors downloaded `SHA256SUMS` to the CI-produced manifest, validates both DMGs, and asserts byte identity.
- The runbook correctly says no GitLab v0.2.0 release is currently claimed and prohibits use of the explicitly unrelated host.

## Safe local validation evidence

All green commands ran in a task-scoped detached worktree populated from the current scoped sources. The overlay was byte-compared with the current scoped files before execution.

| Command or probe | Exit | Result |
| --- | ---: | --- |
| `shellcheck scripts/*.sh` | 0 | Release shell lint green. |
| `swift test` | 0 | Existing four XCTest cases plus five `GitLabReleaseAutomationTests` cases green in the overlay. The release test itself is currently untracked. |
| `swift build` | 0 | Green. |
| `SIGN_IDENTITY=- REQUIRE_DEVELOPER_ID=0 scripts/build-app.sh` | 0 | Universal ad-hoc audit build green in the isolated worktree. |
| `SIGN_IDENTITY=- REQUIRE_DEVELOPER_ID=1 scripts/build-app.sh` | 1 | Expected rejection: production ad-hoc signing is forbidden. |
| positive synthetic preflight | 0 | Exact protected-tag/SHA/runner context accepted. |
| wrong accepted SHA, unprotected tag, missing `relux-release` runner tag | 1 each | Expected fail-closed rejections. |
| release script with missing credentials | 1 | Expected fail-closed rejection before credential decoding/notarization. |
| release script with a wrong Developer ID | 1 | Expected exact-identity rejection before decoding/notarization. |
| upload script with a missing required DMG | 1 | Expected fail-closed rejection before curl. |
| upload script with a checksum mismatch | 1 | Expected checksum rejection before curl. |
| verification script with no job token | 1 | Expected fail-closed rejection before curl. |
| verification script with fake local curl returning tampered downloads | 1 | Expected downloaded checksum rejection. No network was used. |
| Ruby YAML parse of `.gitlab-ci.yml` | 0 | Basic YAML syntax parses. |
| scoped literal-secret scan | 0 | No private-key/token literal matched the targeted patterns. |

Expected-red commands are recorded as exit 1; they are successful negative tests, not green release gates.

The full notarization success path was intentionally not invoked: it requires production Apple credentials and contacts the notary service, which is outside this read-only audit scope.

## Safety record

- The initial and final main-worktree porcelain count was 188; no tracked files were staged, committed, or modified by this audit.
- Test builds, fake-curl responses, and logs were confined to `.temp/TASK-260728-3iwief/`.
- No real GitLab hostname, release API, package registry, remote, tag, upload, notarization request, or secret value was used.
- The curl redirect probe used only two local HTTP listeners and a synthetic value; the board artifact does not contain any credential value.

## Primary references

- curl custom-header redirect warning: <https://curl.se/docs/manpage.html>
- GitLab Releases API and `JOB-TOKEN` authentication: <https://docs.gitlab.com/api/releases/>
- GitLab Generic Package Registry authentication: <https://docs.gitlab.com/user/packages/generic_packages/>
- Apple notarization/stapling workflow: <https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution>
