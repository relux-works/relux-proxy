# TASK-260728-3p6rkz rework results

## Outcome

Addressed every changes-requested finding from the first review:

- legacy Boolean and floating-point `localPort` values are now rejected as
  incompatible types instead of bridging through `NSNumber` to `Int`;
- decoded v1 profiles are strictly validated in their stored form, so host or
  account whitespace blocks the store without rewriting the original payload;
- a fresh controller test now proves that persisted profiles relaunch
  disconnected, with empty diagnostics and no automatic child or retry;
- `CONTRIBUTING.md` now matches the Xcode 16 development baseline in
  `README.md`.

## Regression coverage

- Boolean `true` and integral Double `1080.0` each produce an empty v1 payload,
  bounded migration diagnostic, completion marker, and unchanged legacy keys.
- Persisted surrounding whitespace in either `host` or `account` preserves the
  original bytes, exposes no profiles, reports a blocking persistence error,
  leaves migration incomplete, and blocks mutations.
- A fresh controller created from defaults after connected and failed runtime
  state restores every profile disconnected with empty diagnostics; its fresh
  process factory, readiness monitor, and scheduler remain unused.

## Validation evidence

- Expected-red `swift test --filter TunnelProfileStoreTests` — exit 1; the new
  regressions exposed the two reviewed persistence defects before the fix.
- Post-fix `swift test --filter TunnelProfileStoreTests` — exit 0; 13 tests.
- `swift test --filter relaunchRestoresDisconnectedProfilesWithoutDiagnosticsOrAutomaticProcesses`
  — exit 0; 1 test.
- `make lint` — exit 0.
- `make test` — exit 0; 27 tests in 4 suites.
- `make app` — exit 0; universal application build and signing validation
  succeeded.
- `codesign --verify --deep --strict --verbose=2 dist/ReluxProxy.app` — exit 0.
- `git diff --check -- Sources/ReluxProxy Tests/ReluxProxyTests README.md
  CONTRIBUTING.md docs/current-state.md Makefile Package.swift` — exit 0.
- `lipo -archs dist/ReluxProxy.app/Contents/MacOS/ReluxProxy` — exit 0;
  `x86_64 arm64`.

## Rework delta

Source:

- `Sources/ReluxProxy/TunnelProfile.swift`
- `Sources/ReluxProxy/TunnelProfileStore.swift`

Tests:

- `Tests/ReluxProxyTests/TunnelControllerTests.swift`
- `Tests/ReluxProxyTests/TunnelProfileStoreTests.swift`

Documentation:

- `CONTRIBUTING.md`

## Full task-scoped worktree paths

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

Existing foreign `.spec`, historical `.task-board`, planning, and configuration
changes were not restored, rewritten, staged, committed, or cleaned.
