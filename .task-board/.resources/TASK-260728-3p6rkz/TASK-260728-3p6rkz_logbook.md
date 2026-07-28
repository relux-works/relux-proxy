# TASK-260728-3p6rkz logbook

## 2026-07-28 — lifecycle callback ordering
A readiness result can already be queued when the user cancels a connecting profile. Generation and process identity alone do not distinguish that valid old readiness result from the same generation after an explicit stop. The controller therefore accepts readiness only while the session is still connecting and requestedStop is false. This keeps disconnecting monotonic until the owned child terminates. The regression test delivers ready after disconnect and verifies that state remains disconnecting.

## Scope safety
The worktree contained extensive pre-existing .spec, historical .task-board, planning, and config changes. Implementation touched only the task-scoped source, test, README, current-state, and Makefile paths listed in the implementation-results artifact, plus board state through task-board commands.

## 2026-07-28 — reviewer migration validation findings

Review found that `UserDefaults` bridges Boolean `true` and integral Double
`1080.0` through `as? Int`, so the current legacy-port loader accepts
incompatible stored types instead of producing an empty v1 store and migration
diagnostic. Review also found that persisted v1 host/account fields are passed
through the write-time normalizer, silently accepting and repairing surrounding
whitespace instead of preserving and blocking an invalid payload. Both require
strict read-time type/field validation and regression tests.

The automated suite also needs the contract-required restart assertion showing
that a fresh controller restores every profile disconnected, with empty
diagnostics and no automatic process launch or retry. Reviewer gates themselves
were green: `make lint`, 22 Swift Testing tests, universal `make app`, code-sign
verification, and scoped `git diff --check`.

## 2026-07-28 — strict persisted reads and legacy numeric types

`UserDefaults.object(forKey:)` bridges integer, floating-point, and Boolean
property-list values through `NSNumber`, and Swift's `as? Int` accepts both
Boolean `true` and integral Double `1080.0`. Legacy migration now excludes
`CFBoolean`, rejects floating-point `CFNumber` values, and performs a lossless
signed-integer extraction before port-range validation.

Normalization remains appropriate at user add/edit and legacy-migration
boundaries. Existing v1 JSON is now validated without repair: decoded profiles
must already equal their normalized form before they are exposed or the
migration marker is set. Invalid bytes remain untouched and the store is
blocking. Regression tests cover both decisions plus fresh-controller
disconnected/no-diagnostic/no-auto-launch behavior.

## 2026-07-28 — failed-state cleanup review finding

The second review verified every first-round persistence and restart fix and
reran the strict gates successfully. It found one remaining lifecycle mismatch:
a readiness timeout sets an active session to failed, but the row exposes an
enabled Stop action while the owned child is being reaped. That action marks the
termination as user-requested, so the callback clears the diagnostic and moves
the session through disconnecting to disconnected.

The accepted state model permits failed to transition only through an explicit
new start. Rework must preserve the failure and diagnostic through child cleanup,
avoid the failed-to-disconnected lifecycle action, retain quit-time termination,
and add a deterministic regression for a lifecycle action racing timeout
cleanup.

## 2026-07-28 — failed-state cleanup invariant

An active failed session now explicitly represents an owned child that is still
being reaped. Its lifecycle action is disabled and labeled `Cleaning up…`, and
the controller rejects direct disconnect requests for the same state. The
existing termination request and two-second forced-stop fallback remain active;
normal app shutdown waits for the child callback without changing the failure
or diagnostic.

Two deterministic regressions first reproduced the invalid
`failed -> disconnecting -> disconnected` transition, then verified that the
failure survives both a lifecycle action and quit-time cleanup. A subsequent
explicit start creates a new process generation, clears the old diagnostic, and
continues to reject stale callbacks from the reaped child.

## 2026-07-28 — documentation delivery integrity finding

The third review verified the failed-cleanup rework and reran every strict gate
successfully. It found that the required README and current-state updates both
link to `.spec/legacy-socks-multi-tunnel.md`, while that path is untracked,
absent from `HEAD`, explicitly excluded from the producer task scope, and
classified as foreign by the worktree-safety contract. A scoped task commit
would therefore publish two broken links.

The foreign document also still describes the current release as one-tunnel and
multi-tunnel support as unshipped, contradicting the updated documentation.
Rework must stay within the authorized documentation scope: remove the links or
replace them with an existing tracked, non-contradictory destination, without
modifying, staging, or committing the foreign spec.

## 2026-07-28 — documentation delivery integrity repaired

README now links the shipped multi-profile behavior to the tracked
`docs/current-state.md` inventory and distinguishes it from the separately
tracked future-VPN specification index. The current-state page now links its
user workflow to the tracked README and describes the implementation directly.
Neither page references the foreign, untracked legacy contract. `git diff
--check`, the stale-link check, `make lint`, `make test` (29 tests), and
universal signed `make app` all exited 0 after the repair.
