# TASK-260728-3p6rkz reviewer verdict — round 2

## Verdict

**changes_requested → `to-dev`**

The rework correctly resolves every finding from the first review: legacy
Boolean and floating-point ports are rejected, stored v1 fields are validated
without normalization or overwrite, the fresh-controller no-reconnect case is
covered, and the Xcode baseline is consistent. The architecture and all strict
validation gates remain sound.

One lifecycle-contract violation remains.

## Required finding

### A failed readiness attempt can be cleared without a new start

`TunnelController.handleReadiness` sets an active session to `.failed` on
timeout, asks the child to terminate, and schedules the same-child forced-stop
fallback (`Sources/ReluxProxy/TunnelController.swift:404-414`). While that
cleanup is pending, `TunnelProfileRow` exposes an enabled **Stop** button for
the active failed session (`Sources/ReluxProxy/MenuContentView.swift:235-250`).
The button calls `disconnect`, which changes the session to `.disconnecting`
and marks it as a requested stop (`TunnelController.swift:300-324`).
Termination then clears the diagnostic and reports `.disconnected`
(`TunnelController.swift:433-445`).

This creates the visible path:

```text
failed → disconnecting → disconnected
```

The accepted contract permits only `failed → connecting` and explicitly says
that a profile remains failed until the user starts it again. The current path
also removes the failure diagnostic before a retry, so the row and aggregate
status can lose the failure during the two-second cleanup window.

Required rework:

- keep the failed status and diagnostic visible while its owned child is being
  reaped;
- do not expose an action that reclassifies that failure as a user-requested
  disconnect; a disabled cleanup state or controller semantics that preserve
  the prior failure are both viable;
- retain orderly quit behavior for that child;
- add a deterministic regression that times out readiness, invokes the
  lifecycle action before termination, emits termination, and proves the
  session remains failed with its diagnostic until an explicit new start;
- prove the new start creates a new generation and clears the old diagnostic.

## Reviewer validation

- `make lint` — exit 0.
- `make test` — exit 0; 27 tests in 4 suites.
- `make app` — exit 0; universal arm64/x86_64 application built.
- `codesign --verify --deep --strict --verbose=2 dist/ReluxProxy.app` — exit 0.
- `lipo -archs dist/ReluxProxy.app/Contents/MacOS/ReluxProxy` — exit 0;
  `x86_64 arm64`.
- Scoped `git diff --check` — exit 0.
- The spawned reviewer run has no active child goal.

## Reviewed task scope

Source:

- `Sources/ReluxProxy/MenuContentView.swift`
- `Sources/ReluxProxy/ReluxProxyApp.swift`
- `Sources/ReluxProxy/SSHCommandBuilder.swift`
- `Sources/ReluxProxy/TunnelConfiguration.swift`
- `Sources/ReluxProxy/TunnelController.swift`
- `Sources/ReluxProxy/TunnelProfile.swift`
- `Sources/ReluxProxy/TunnelProfileStore.swift`
- `Sources/ReluxProxy/TunnelRuntime.swift`

Tests:

- `Tests/ReluxProxyTests/LocalPortProbeTests.swift`
- `Tests/ReluxProxyTests/TunnelConfigurationTests.swift`
- `Tests/ReluxProxyTests/TunnelControllerTests.swift`
- `Tests/ReluxProxyTests/TunnelProfileStoreTests.swift`

Documentation and build:

- `README.md`
- `CONTRIBUTING.md`
- `docs/current-state.md`
- `Makefile`

The reviewer modified no product code. Existing foreign `.spec`, historical
`.task-board`, `.planning`, `.research`, and configuration worktree changes
were not restored, rewritten, staged, committed, or cleaned.
