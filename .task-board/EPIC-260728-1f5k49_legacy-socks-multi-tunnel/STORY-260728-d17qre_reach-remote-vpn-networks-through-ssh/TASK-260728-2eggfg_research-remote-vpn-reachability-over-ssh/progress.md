## Status
done

## Review
required

## Task Class
research

## Estimate
estimated(fibonacci(5))

## Blocked By
- (none)

## Blocks
- (none)

## Checklist
- [x] Model ssh -D traffic origin routing DNS and protocol limits
- [x] Provide a safe redacted diagnostic decision tree for both Macs
- [x] Compare SOCKS-aware configuration sshuttle tun2socks Network Extension and ssh -w
- [x] Cite authoritative OpenSSH macOS and relevant VPN behavior sources
- [x] Recommend a v0.2.0 action or create exact follow-up implementation scope
- [x] Findings written to file
- [x] Key aspects highlighted
- [x] Fact-checking performed — claims verified, sources cited
- [x] Findings linked on the board as a new task-scoped outcome resource
- [x] All questions from task description answered
- [x] Important findings, decisions, anomalies, or regressions recorded in logbook when relevant
- [x] Implementation matches AC
- [x] Solution fits project architecture
- [x] Tests green
- [x] If review does not accept the work — verdict evidence added and status routed by the explicit verdict branches

## Notes
spawn agent resolution: Agent selection: codex via explicit_override
spawn launch composition: degraded_contract_unavailable; contract=agents-infra.child-launch-composition; provider=codex; schema=1; diagnostic=composition_contract_unavailable; bare child launch retained
spawn queued: [analyst] researcher (codex) (run=RUN-260728-eb68b7, max_parallel=20)
spawn run started: [analyst] researcher (codex) (run=RUN-260728-eb68b7)
Research handoff evidence: attached TASK-260728-2eggfg_remote-vpn-reachability-over-ssh.md and TASK-260728-2eggfg_logbook.md. OpenSSH direct-tcpip destination sockets originate in the authenticated remote sshd worker; proxy-side DNS is used only when the client preserves the hostname; ssh -D implements TCP CONNECT only and does not install source-Mac routes. Controlled loopback fixture passed after explicitly asserting the expected-red local IPv6 resolution branch: first fixture run exit 97 expected-red; revised fixture exit 0; sshd config/effective-policy diagnostics exit 0; document content assertion exit 0; git diff --check exit 0. Created follow-up TASK-260728-3rs1x2 for v0.2.0 SOCKS boundary and reachability guidance. No production source or system/remote VPN configuration was changed.
agent completed: [analyst] researcher (codex) (exit=0)
spawn run completed: codex (run=RUN-260728-eb68b7, pid=41228, exit=0)
spawn agent resolution: Agent selection: codex via explicit_override
spawn launch composition: degraded_contract_unavailable; contract=agents-infra.child-launch-composition; provider=codex; schema=1; diagnostic=composition_contract_unavailable; bare child launch retained
spawn queued: [reviewer] reviewer (codex) (run=RUN-260728-d72e82, max_parallel=20)
spawn run started: [reviewer] reviewer (codex) (run=RUN-260728-d72e82)
Reviewer verdict accepted. Independent review mapped all five ACs; reran loopback fixture successfully; verified numeric SOCKS, SOCKS5h, remote sshd-sess socket ownership, expected local IPv6 failure, and UDP-associate rejection; make test passed 22 tests and make lint passed. Primary OpenSSH V_10_2_P1, RFC, curl, Apple Network Extension/PF, sshuttle, and HEV claims were fact-checked. Verdict evidence: TASK-260728-2eggfg_review-verdict.md. Follow-up TASK-260728-3rs1x2 is correctly scoped for v0.2.0 guidance. Conditional non-acceptance checklist item is not applicable because this review accepts.
agent completed: [reviewer] reviewer (codex) (exit=0)
spawn run completed: codex (run=RUN-260728-d72e82, pid=89816, exit=0)

## Precondition Resources
- [TASK-260728-2eggfg_problem-statement.md](file://TASK-260728-2eggfg/TASK-260728-2eggfg_problem-statement.md) — Observed remote VPN reachability problem

## Outcome Resources
- [TASK-260728-2eggfg_spawn-log_-analyst--researcher--codex-_RUN-260728-eb68b7.log](file://TASK-260728-2eggfg/TASK-260728-2eggfg_spawn-log_-analyst--researcher--codex-_RUN-260728-eb68b7.log) — System spawn log captured by task-board
- [TASK-260728-2eggfg_remote-vpn-reachability-over-ssh.md](file://TASK-260728-2eggfg/TASK-260728-2eggfg_remote-vpn-reachability-over-ssh.md) — Fact-checked OpenSSH and macOS VPN research, controlled fixture evidence, redacted two-Mac runbook, option matrix, and v0.2.0 recommendation
- [TASK-260728-2eggfg_logbook.md](file://TASK-260728-2eggfg/TASK-260728-2eggfg_logbook.md) — Research logbook of packet-origin findings, product decisions, controlled-fixture anomalies, and unresolved environment facts
- [TASK-260728-2eggfg_spawn-log_-reviewer--reviewer--codex-_RUN-260728-d72e82.log](file://TASK-260728-2eggfg/TASK-260728-2eggfg_spawn-log_-reviewer--reviewer--codex-_RUN-260728-d72e82.log) — System spawn log captured by task-board
- [TASK-260728-2eggfg_review-verdict.md](file://TASK-260728-2eggfg/TASK-260728-2eggfg_review-verdict.md) — Accepted reviewer verdict with AC mapping, independent fixture/test evidence, source fact-check, architecture fit, and non-blocking source-checkout note

## Created
2026-07-28T10:55:58Z

## Last Update
2026-07-28T11:32:48Z

## Assigned To
[reviewer] reviewer (codex)
