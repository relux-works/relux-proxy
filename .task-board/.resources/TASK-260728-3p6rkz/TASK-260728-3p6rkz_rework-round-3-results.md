# TASK-260728-3p6rkz rework round 3

## Outcome

Resolved the second-review lifecycle finding without changing the accepted
state model:

- an active failed session is treated as failed-process cleanup;
- direct disconnect requests cannot reclassify that failure as a requested
  stop;
- the SwiftUI row shows a disabled, accessible `Cleaning up…` action while the
  owned child is being reaped;
- readiness-timeout diagnostics remain visible through termination and normal
  app shutdown;
- an explicit retry creates a new process generation, clears the prior
  diagnostic, and ignores callbacks from the reaped child.

## Files changed in this rework

Source:

- `Sources/ReluxProxy/MenuContentView.swift`
- `Sources/ReluxProxy/TunnelController.swift`

Tests:

- `Tests/ReluxProxyTests/TunnelControllerTests.swift`

## Full task-scoped worktree set

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

## Validation evidence

Expected-red regression gates before the implementation:

- `swift test --filter TunnelControllerTests.readinessFailureCannotBeClearedBeforeExplicitRestart`
  — exit 1, expected because the existing controller changed the timed-out
  session to disconnecting/disconnected and cleared its diagnostic.
- `swift test --filter TunnelControllerTests.shutdownWaitsForFailedReadinessCleanupWithoutErasingFailure`
  — exit 1, expected because shutdown reclassified the active failure as a
  requested stop.

Green validation after the implementation:

- `swift test --filter TunnelControllerTests.readinessFailureCannotBeClearedBeforeExplicitRestart`
  — exit 0.
- `swift test --filter TunnelControllerTests.shutdownWaitsForFailedReadinessCleanupWithoutErasingFailure`
  — exit 0.
- `make lint` — exit 0.
- `make test` — exit 0; 29 tests in 4 suites.
- `make app` — exit 0; universal application build succeeded and the build
  script verified its signature.
- `codesign --verify --deep --strict --verbose=2 dist/ReluxProxy.app` — exit 0.
- `lipo -archs dist/ReluxProxy.app/Contents/MacOS/ReluxProxy` — exit 0;
  `x86_64 arm64`.
- scoped `git diff --check` across the full task file set — exit 0.

## Worktree safety

Pre-existing changes in `.spec`, historical `.task-board`, `.planning`,
`.research`, and configuration files were preserved. This rework modified only
the three files listed above, its task-scoped temporary evidence, and board
state/resources through `task-board`; nothing was staged, committed, restored,
cleaned, or rewritten outside that scope.
