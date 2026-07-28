# TASK-260728-3iwief reviewer verdict — RUN-260728-5425c3

Date: 2026-07-28  
Role: reviewer  
Verdict: **ACCEPTED**

## Scope and method

Fresh read-only audit of the current repository-local GitLab v0.2.0 release
implementation. Validation ran from an isolated snapshot containing all current
`Package.swift`, `Sources`, `Tests`, `Resources`, `scripts`,
`.gitlab-ci.yml`, `.github`, `Makefile`, `README.md`, `docs`, `.spec`, and
`release-notes` content. No source file was edited, staged, committed, tagged,
or pushed.

The run was not goal-bound (`task-board spawn goal` reported no active run
goal). No reviewer `commit_ack` was supplied.

## Acceptance evidence

### Protected tag, project, SHA, and runner

- `.gitlab-ci.yml` admits the release only for exact tag `v0.2.0`; other tags
  are rejected at workflow level. Both production jobs require the `macos` and
  `relux-release` runner tags, and the release job is serialized through
  `relux-production-release`.
- `scripts/gitlab-release-preflight.sh` requires an exact protected push,
  confirmed HTTPS GitLab host, exact namespace/project, positive numeric
  `CI_PROJECT_ID`, exact equality with protected
  `RELUX_GITLAB_PROJECT_ID`, full lowercase 40-character accepted SHA equality,
  checked-out `HEAD` equality, and both runner tags.
- The production job checks the protected project ID before invoking release or
  verification scripts. Each script reruns preflight before constructing
  package, Release, or download URLs.
- The local positive matrix supplied the current 40-character `HEAD` to both SHA
  variables only to exercise the equality contract. Production remains
  fail-closed until the post-review scoped commit SHA is stored as
  `RELUX_ACCEPTED_RELEASE_SHA`.

### Signing, notarization, stapling, Gatekeeper, and checksums

- The release path imports credentials into a disposable keychain, requires the
  exact Developer ID Application identity
  `Relux Works, LLC (262RZ595FP)`, verifies the app authority and team ID, and
  rejects ad-hoc or unavailable production signing.
- The app is built for `arm64` and `x86_64` with hardened runtime. The DMG is
  signed, submitted with `notarytool --wait`, required to report `Accepted`,
  logged, stapled, staple-validated, code-signature-verified again, and assessed
  by Gatekeeper before stable-name copying or checksum generation.
- Upload revalidates the checksum file and stable/versioned byte identity,
  refuses redirects, and requires exact HTTP `201`.
- Published verification requires the exact Release tag and commit, exactly
  three same-project package links, byte-identical published/local
  `SHA256SUMS`, valid per-asset hashes, and byte-identical stable/versioned
  DMGs.

### Redirect credential isolation

- `verify-gitlab-release.sh` does not use curl automatic redirects. It follows
  only bounded manual HTTPS redirects, attaches `JOB-TOKEN` only when the next
  URL's byte-exact origin equals `CI_SERVER_URL`, and fetches a cross-origin
  object URL without that header.
- The real TLS regression started two loopback origins with a synthetic marker
  token. The confirmed GitLab origin received authentication on the initial and
  same-origin requests; two cross-origin asset requests received no
  `JOB-TOKEN`, and their logs contained no token value.
- HTTP, missing `Location`, relative/malformed `Location`, more than five hops,
  unexpected status, and wrong-project metadata all failed closed.
- This matches the current primary contracts: the
  [GitLab Releases API](https://docs.gitlab.com/api/releases/) accepts
  `CI_JOB_TOKEN` and defines the direct download endpoint; the
  [Generic Package Registry](https://docs.gitlab.com/user/packages/generic_packages/)
  supports job-token uploads and documents `201 Created`; and the
  [curl manual](https://curl.se/docs/manpage.html) warns that arbitrary custom
  headers can be sent on redirected requests.

## Independent validation results

| Gate | Result |
| --- | --- |
| ShellCheck | pass, all 6 shell scripts |
| `/bin/bash -n` | pass, all 6 shell scripts |
| YAML parsing | pass, `.gitlab-ci.yml` and 2 GitHub workflow files |
| GitLab YAML contract assertions | pass |
| `swift format lint --recursive --strict Sources Tests` | pass |
| `swift test` | pass, 51 tests in 9 suites |
| `swift build` | pass |
| Universal ad-hoc app build | pass |
| App inspection | `x86_64 arm64`, version `0.2.0`, build `20260728`, valid signature |
| Protected preflight matrix | pass, 1 positive + 20 expected failures |
| Offline upload matrix | pass, 1 positive + 5 expected failures |
| Offline published-verification matrix | pass, 1 positive + 7 expected failures |
| Release/signing guard matrix | pass, 5 expected failures |
| Snapshot/source parity | pass |
| Non-board source fingerprint | unchanged, 135 files |
| `git diff --check` / staging | pass / 0 staged files |
| Secret-shaped literal, tracing, and whitespace scan | pass |

The unchanged non-board manifest digest was
`d3ac391d25dc843c32908eb2b809502a21616ca8bb87f9469e1512ffb63a08d7`.

## Safety

- All publication simulations used synthetic credentials and either exported
  local curl doubles or TLS listeners bound only to `127.0.0.1`.
- No GitLab project API, package registry, Release endpoint, Apple notarization
  service, upload, source push, or external publication action was invoked.
- The only configured repository remote is SSH on `github.com`; no local
  `v0.2.0` tag exists.
- Redirect headers, bodies, and any signed redirect URL remain under temporary
  storage removed by the verifier's exit trap. No real secret value was read or
  printed.
- The original source snapshot and every non-board/non-temp worktree file kept
  the same pre/post content fingerprint.

## Corrected reviewer-harness attempts

Two reviewer harness mistakes were retained as anomalies, not counted as
product failures or passes:

1. The first YAML contract assertion used unavailable
   `Psych.safe_load_file`; it was rerun successfully with
   `YAML.safe_load(File.read(...))`.
2. The first static trace scan was overly broad and matched expected
   `codesign --verbose` diagnostics while Bash negation allowed the wrapper to
   continue. A focused shell-xtrace/curl-trace assertion was rerun and passed.

## Conclusion

The mandatory redirect credential-safety and exact project-ID rework satisfies
the task acceptance criteria and fits the repository's separated
preflight/build/upload/verify architecture. The reviewer verdict is accepted.
External v0.2.0 publication remains intentionally blocked on the separately
tracked Relux-owned GitLab target, authorization, protected runner/variables,
scoped commit, and Apple credentials.
