# TASK-260728-3iwief developer logbook — RUN-260728-e619f0

## 2026-07-28

- Entered `development` as the assigned developer and read the mandatory rework
  brief plus the prior changes-requested evidence.
- Preserved the heavily dirty shared checkout. Scoped release files were
  already untracked, as the rework brief anticipated; no stage, commit, push,
  tag, or external publication action was performed.
- Traced the token leak to a custom `JOB-TOKEN` combined with curl automatic
  redirects. Replaced it with a bounded manual HTTPS redirect loop that
  authenticates only byte-exact confirmed-GitLab origins.
- Added exact Release-link metadata validation and removed automatic redirect
  following from package upload, requiring HTTP 201.
- Added protected `RELUX_GITLAB_PROJECT_ID` validation to preflight, CI, tests,
  runbook, and release evidence.
- Added a Swift Testing regression backed by two real TLS loopback origins. It
  proves same-origin authentication, tokenless cross-origin downloads, and
  fail-closed unsafe redirect behavior without real network or credential use.
- Discovered that replacing the verifier reset its executable bit. The first
  direct offline matrix surfaced exit 126; restored mode 0755 and retained that
  failure in the evidence.
- Corrected two task-local validation-harness issues: a non-executable syntax
  wrapper (exit 126) and an unexported synthetic fixture variable (offline
  matrix exit 1). Neither was represented as a passing gate.
- Validated the exact current-source snapshot: shell/YAML/format gates, 51 Swift
  tests in 9 suites, Swift build, universal ad-hoc app build and inspection,
  preflight 1+20, upload 1+5, verification 1+7, and release guards 5 expected
  failures.
- Confirmed source parity and an identical pre/post non-board worktree
  fingerprint. Confirmed the sole GitHub remote, absent local v0.2.0 tag,
  no secret/tracing matches, and no external GitLab or Apple release action.
- Prepared task-scoped implementation and validation evidence for fresh review.
