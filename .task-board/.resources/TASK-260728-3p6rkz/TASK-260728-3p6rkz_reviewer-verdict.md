# TASK-260728-3p6rkz reviewer verdict

## Verdict

**changes_requested → `to-dev`**

The overall architecture is sound: stable UUID-backed profiles, one session
object per profile, generation-guarded callbacks, local-only OpenSSH arguments,
isolated diagnostics, coordinated shutdown, and stable SwiftUI row identity all
fit the accepted contract. Reviewer-owned lint, test, universal build, and
signature gates pass. The following contract violations and evidence gap must
be corrected before acceptance.

## Required findings

### 1. Incompatible legacy numeric types can migrate as valid ports

`TunnelProfileStore.legacyPort()` uses `value as? Int`
(`Sources/ReluxProxy/TunnelProfileStore.swift:168`). Values returned by
`UserDefaults` are bridged `NSNumber` instances, and Swift accepts both a
Boolean and an integral Double through that cast:

```text
bool __NSCFBoolean Optional(1)
double __NSCFNumber Optional(1080)
string NSTaggedPointerString nil
int __NSCFNumber Optional(1080)
```

Therefore a legacy Boolean `true` migrates to port `1`, and `1080.0` migrates
to port `1080`, instead of taking contract section 2.2 step 3: write an empty v1
payload and surface a bounded migration diagnostic for an incompatible stored
type.

Required rework:

- distinguish a genuine property-list integer from Boolean and floating-point
  `NSNumber` values;
- add regression tests for at least Boolean `true` and integral Double
  `1080.0`;
- assert the resulting v1 payload is empty, the diagnostic and completion
  marker are present, and the legacy values remain untouched.

### 2. Invalid persisted v1 fields are silently normalized and allowed to run

`loadExistingPayload` calls `TunnelProfileValidator.normalize`
(`Sources/ReluxProxy/TunnelProfileStore.swift:96`), while
`TunnelProfile.normalized()` trims host and account
(`Sources/ReluxProxy/TunnelProfile.swift:17`). A stored v1 payload containing
`"host": " work-bastion "` or `"account": " ops "` is therefore accepted,
normalized only in memory, and can be started. A later mutation also rewrites
the previously invalid bytes.

Contract section 2.1 requires an invalid required field to leave the payload
untouched, report a persistence error, and refuse to start affected profiles.
Normalization is appropriate for legacy migration and user add/edit input, but
not for validating an already persisted v1 payload.

Required rework:

- strictly validate decoded v1 fields in their stored form, without repairing
  them;
- preserve the original Data and block starts/mutations when stored host or
  account is not already normalized;
- add regression coverage asserting the bytes are unchanged, profiles are not
  exposed, a blocking persistence error is reported, and the migration marker
  is not completed for that invalid payload.

### 3. Mandatory restart/no-auto-reconnect evidence is absent

The suite covers profile-store relaunch and controller shutdown, but it does not
demonstrate contract section 8 item 5: after a runtime restart, every profile is
disconnected, diagnostics are empty, and no child/retry is launched.

Required rework:

- construct a fresh controller/process factory from the same persisted defaults
  after a prior controller has runtime state;
- assert all restored sessions are disconnected with empty diagnostics and the
  fresh process factory has launched no child.

## Documentation follow-up

`README.md:53` now requires Xcode 16, while `CONTRIBUTING.md:19` still declares
Xcode 15.3. Reconcile the development baseline during rework.

## Reviewer validation

- `make lint` — exit 0.
- `make test` — exit 0; 22 tests in 4 suites.
- `make app` — exit 0; universal arm64/x86_64 application built.
- `codesign --verify --deep --strict --verbose=2 dist/ReluxProxy.app` — exit 0.
- `git diff --check` over scoped source/test/doc/build files — exit 0.

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

Docs/build:

- `README.md`
- `docs/current-state.md`
- `Makefile`

The reviewer modified no product code. Existing foreign `.spec`, historical
`.task-board`, planning, and configuration worktree changes were not restored,
rewritten, staged, committed, or cleaned.
