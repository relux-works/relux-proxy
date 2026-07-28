## Status
done

## Review
required

## Task Class
code

## Estimate
estimated(fibonacci(5))

## Blocked By
- (none)

## Blocks
- (none)

## Checklist
- [x] Record sanitized preflight for GitHub repository access and existing tgfs runner
- [x] Register a second runner in a separate directory and service without stopping or modifying tgfs
- [x] Assign unique relux-proxy-release label and verify GitHub reports the runner online and idle
- [x] Bind release workflow to self-hosted macOS x64 relux-proxy-release and full Xcode
- [x] Add or update workflow contract tests and GitHub release runbook
- [x] Run Swift tests lint shell workflow validation and remote runner smoke checks
- [x] Prove registration tokens and secret values are absent from outcome and repository
- [x] Code written per task description and AC
- [x] Relevant tests written for new or changed behavior and passing
- [x] Lint clean
- [x] Relevant build/validation commands run after changes and build not broken
- [x] New outcome artifact attached on the board with a task-scoped name when the work produces notes, logs, screenshots, or other deliverables
- [x] Important findings, decisions, anomalies, or regressions recorded in logbook when relevant
- [x] Implementation matches AC
- [x] Solution fits project architecture
- [x] Tests green
- [x] If review does not accept the work — verdict evidence added and status routed by the explicit verdict branches

## Notes
spawn agent resolution: Agent selection: codex via explicit_override
spawn launch composition: degraded_contract_unavailable; contract=agents-infra.child-launch-composition; provider=codex; schema=1; diagnostic=composition_contract_unavailable; bare child launch retained
spawn queued: [implementer] developer (codex) (run=RUN-260728-cbda41, max_parallel=20)
spawn run started: [implementer] developer (codex) (run=RUN-260728-cbda41)
Developer handoff: registered GitHub runner relux-proxy-release (runner ID 21) in /Users/administrator/actions-runner-relux-proxy-release with separate LaunchAgent actions.runner.relux-works-relux-proxy.relux-proxy-release. GitHub reports online/idle with self-hosted, macOS, X64, relux-proxy-release. Existing tgfs service remained running and four protected fingerprints are unchanged. release.yml is exact-v0.2.0, dedicated-label-only, full-Xcode, fail-closed on context/secrets/Developer ID, and cleans its temporary keychain. Final gates exit 0: targeted tests, make test (55 tests), make lint, shellcheck, actionlint, make build, git diff --check, remote Xcode/listener smoke, GitHub state assertion, tgfs immutability, and task-scoped secret scan. No v0.2.0 tag or Release was created. Evidence and logbook attached.
agent completed: [implementer] developer (codex) (exit=0)
spawn run completed: codex (run=RUN-260728-cbda41, pid=25729, exit=0)
spawn agent resolution: Agent selection: codex via explicit_override
spawn launch composition: degraded_contract_unavailable; contract=agents-infra.child-launch-composition; provider=codex; schema=1; diagnostic=composition_contract_unavailable; bare child launch retained
spawn queued: [reviewer] reviewer (codex) (run=RUN-260728-b4a61c, max_parallel=20)
spawn run started: [reviewer] reviewer (codex) (run=RUN-260728-b4a61c)
Reviewer verdict: changes requested. The always cleanup uses set -e and stops when security delete-keychain fails, so RELEASE_TEMP removal is never attempted and decoded asc.p8 plus the signing keychain can remain on the persistent runner. Failure-path harness reproduced exit 37 with no temp-removal attempt and both simulated secret-bearing files remaining. Preserve path guards, make cleanup operations independent while returning failure, add a regression test, and rerun all gates. See TASK-260728-35ogr2_reviewer-verdict.md.
agent completed: [reviewer] reviewer (codex) (exit=0)
spawn run completed: codex (run=RUN-260728-b4a61c, pid=40850, exit=0)
spawn agent resolution: Agent selection: codex via explicit_override
spawn launch composition: degraded_contract_unavailable; contract=agents-infra.child-launch-composition; provider=codex; schema=1; diagnostic=composition_contract_unavailable; bare child launch retained
spawn queued: [implementer] developer (codex) (run=RUN-260728-cfefe9, max_parallel=20)
spawn run started: [implementer] developer (codex) (run=RUN-260728-cfefe9)
Developer rework handoff: fixed the reviewer-reproduced persistent-runner credential retention path by moving guarded cleanup to scripts/github-release-cleanup.sh. Keychain deletion and release-temp removal now run independently while preserving the first nonzero status; the new Swift regression simulates security exit 37 and proves the keychain file, asc.p8, and temp directory are removed. Final exits: targeted tests 0 (5), make test 0 (56), make lint 0, shellcheck 0, actionlint 0, make build 0, git diff --check 0, remote Xcode/listener smoke 0, GitHub exact runner-state 0, tgfs fingerprint assertion 0, tag/Release absence 0, and post-evidence credential scan 0. Development evidence also records the expected targeted red exit 1, lint rework exit 2, and malformed scan invocation exit 1. Runner ID 21 remains online/idle; both services are healthy and tgfs fingerprints unchanged. No push, tag, Release, runner reconfiguration, or secret-value query occurred. Sanitized evidence and logbook were updated.
agent completed: [implementer] developer (codex) (exit=0)
spawn run completed: codex (run=RUN-260728-cfefe9, pid=52962, exit=0)
spawn agent resolution: Agent selection: codex via explicit_override
spawn launch composition: degraded_contract_unavailable; contract=agents-infra.child-launch-composition; provider=codex; schema=1; diagnostic=composition_contract_unavailable; bare child launch retained
spawn queued: [reviewer] reviewer (codex) (run=RUN-260728-4ffc2c, max_parallel=20)
spawn run started: [reviewer] reviewer (codex) (run=RUN-260728-4ffc2c)
Reviewer verdict: accepted. Independent review confirms the cleanup rework closes the persistent-runner credential-retention path; targeted and full Swift tests, lint, ShellCheck, actionlint, build, preflight matrix, GitHub runner state, remote Xcode/listener smoke, tgfs service and fingerprint immutability, tag/Release absence, and sanitized credential-payload scan all pass. See TASK-260728-35ogr2_reviewer-acceptance.md.
agent completed: [reviewer] reviewer (codex) (exit=0)
spawn run completed: codex (run=RUN-260728-4ffc2c, pid=65887, exit=0)

## Precondition Resources
- [TASK-260728-35ogr2_runner-brief.md](file://TASK-260728-35ogr2/TASK-260728-35ogr2_runner-brief.md) — Authorized GitHub runner configuration and safety boundary

## Outcome Resources
- [TASK-260728-35ogr2_spawn-log_-implementer--developer--codex-_RUN-260728-cbda41.log](file://TASK-260728-35ogr2/TASK-260728-35ogr2_spawn-log_-implementer--developer--codex-_RUN-260728-cbda41.log) — System spawn log captured by task-board
- [TASK-260728-35ogr2_runner-evidence.md](file://TASK-260728-35ogr2/TASK-260728-35ogr2_runner-evidence.md) — Sanitized runner configuration, reviewer rework, immutability, validation, and credential-scan evidence
- [TASK-260728-35ogr2_logbook.md](file://TASK-260728-35ogr2/TASK-260728-35ogr2_logbook.md) — Task decisions, findings, reviewer rework, anomalies, and safety-boundary logbook
- [TASK-260728-35ogr2_spawn-log_-reviewer--reviewer--codex-_RUN-260728-b4a61c.log](file://TASK-260728-35ogr2/TASK-260728-35ogr2_spawn-log_-reviewer--reviewer--codex-_RUN-260728-b4a61c.log) — System spawn log captured by task-board
- [TASK-260728-35ogr2_reviewer-verdict.md](file://TASK-260728-35ogr2/TASK-260728-35ogr2_reviewer-verdict.md) — Reviewer changes-requested verdict with cleanup failure-path evidence and rework requirements
- [TASK-260728-35ogr2_spawn-log_-implementer--developer--codex-_RUN-260728-cfefe9.log](file://TASK-260728-35ogr2/TASK-260728-35ogr2_spawn-log_-implementer--developer--codex-_RUN-260728-cfefe9.log) — System spawn log captured by task-board
- [TASK-260728-35ogr2_spawn-log_-reviewer--reviewer--codex-_RUN-260728-4ffc2c.log](file://TASK-260728-35ogr2/TASK-260728-35ogr2_spawn-log_-reviewer--reviewer--codex-_RUN-260728-4ffc2c.log) — System spawn log captured by task-board
- [TASK-260728-35ogr2_reviewer-acceptance.md](file://TASK-260728-35ogr2/TASK-260728-35ogr2_reviewer-acceptance.md) — Final reviewer acceptance with independent local, GitHub, remote-host, immutability, and credential-scan evidence

## Created
2026-07-28T17:38:00Z

## Last Update
2026-07-28T18:42:26Z

## Assigned To
[reviewer] reviewer (codex)
