# TASK-260728-2mjju4 validation report

Date: 2026-07-28  
Role: tester  
Platform: macOS 26.0, Apple Swift 6.3.2, Xcode 26.5

## Outcome

The accepted multi-profile implementation is validated for deterministic
concurrent lifecycle behavior, SSH argv construction, persistence and migration,
port conflicts, edit/removal guards, per-profile diagnostics, shutdown, and
packaged macOS application structure.

The final local artifact is:

`dist/ReluxProxy.app`

It is an ad-hoc-signed universal `x86_64 arm64` application bundle for the
task-local validation boundary. Its executable is
`Contents/MacOS/ReluxProxy`; `Contents/Info.plist` is valid and declares
`CFBundleExecutable=ReluxProxy`, `CFBundleIdentifier=works.relux.proxy`,
`CFBundlePackageType=APPL`, `LSMinimumSystemVersion=14.0`, and
`LSUIElement=true`.

## Acceptance evidence

1. **Two simultaneous independent tunnels**
   - `runsConcurrentSessionsWithIndependentStateAndDiagnostics` starts two
     independent process handles on `127.0.0.1:1080` and
     `127.0.0.1:1081`, marks both connected, fails the second with exit status
     17, and proves the first remains active and running.
   - The same test then stops the first without changing the second profile's
     retained failure.
   - `occupiedPortFailureDoesNotDisturbConnectedProfile` and
     `readinessTimeoutAndCleanupRemainIsolated` cover failure isolation.

2. **IP, hostname, alias, account precedence, and argv safety**
   - Parameterized Swift tests cover `203.0.113.10`,
     `bastion.example.net`, and `work-bastion`.
   - Empty Account emits a bare destination. A non-empty Account emits the
     separate suffix `-l <account> <destination>`, preserving OpenSSH alias
     resolution while overriding only the account.
   - Exact argv is asserted for `/usr/bin/ssh`, including
     `-D 127.0.0.1:<port>`.
   - Shell metacharacters remain one literal array element; no `/bin/sh` or
     `-c` is emitted. `SystemTunnelProcess` is also exercised with a direct
     executable URL and argument array.

3. **Persistence, migration, conflicts, mutation, diagnostics, shutdown**
   - Store tests cover clean and legacy migration, one-time migration,
     incompatible legacy values, persistence/relaunch, stable UUIDs, duplicate
     ports, invalid/newer payload preservation, and non-resurrection after
     deletion.
   - A real loopback listener fixture proves OS occupied-port detection.
   - Controller tests cover active edit/removal rejection, per-session bounded
     diagnostics, stale callback isolation, readiness failure cleanup,
     coordinated two-child shutdown, forced-stop scheduling, and disconnected
     relaunch state.
   - Runtime tests use only controlled local executables and deterministic fake
     probes; they cover stderr capture, normal termination, forced termination,
     readiness ready/timeout/cancellation, stopped-process suppression, and
     scheduler cancellation.

4. **Tests, build, and bundle**
   - `make test`: exit 0; 44 tests in 7 Swift Testing suites passed.
   - `make app`: exit 0.
   - `SIGN_IDENTITY=- make app`: exit 0; rebuilt the retained validation
     artifact ad hoc to remain inside the no-release-signing scope.
   - Executable-bit, plist, universal-architecture, and codesign verification
     checks all exit 0.

5. **Installed-Mac usage**
   - `README.md` now documents two distinct
     `127.0.0.1:<saved-port>` client endpoints and two
     `curl --socks5-hostname` exit-identity checks against a user-authorized
     endpoint.
   - It also asks the operator to disconnect one profile, repeat the request
     through the remaining profile, and confirm its identity is unchanged.
   - This physical step was not automated because no authorized external SSH
     hosts or exit-identity endpoint were provided. No external traffic,
     credentials, or private host data were used by the suite.

## Coverage

Final `swift test --enable-code-coverage`: exit 0; 44 tests passed.

Affected non-UI tunnel code:

- 1,106 of 1,202 lines covered: **92.01%**
- `SSHCommandBuilder.swift`: 100.00%
- `TunnelConfiguration.swift`: 100.00%
- `TunnelController.swift`: 87.86%
- `TunnelProfile.swift`: 88.46%
- `TunnelProfileStore.swift`: 91.46%
- `TunnelRuntime.swift`: 97.93%

The whole executable is 54.62% because `MenuContentView.swift` and
`ReluxProxyApp.swift` SwiftUI entry/view bodies are not driven by these
non-UI unit and local integration tests.

## Validation command ledger

Every validation/gate command was run directly without `tee`.

### Green gates

- `swift test --filter TunnelControllerTests`: exit 0; 10 tests.
- `swift test --filter TunnelRuntimeTests`: exit 0; 6 tests after repair.
- `swift test --filter PackagingAndUsageTests`: exit 0; 3 tests.
- `swift test --filter TunnelConfigurationTests`: exit 0; 8 tests.
- `swift test --enable-code-coverage`: exit 0; final run 44 tests.
- `xcrun llvm-cov report ...`: exit 0; final report above.
- `make lint`: exit 0 after repair.
- `make test`: exit 0; 44 tests.
- `make app`: exit 0.
- `SIGN_IDENTITY=- make app`: exit 0.
- `/bin/test -x dist/ReluxProxy.app/Contents/MacOS/ReluxProxy`: exit 0.
- `/usr/bin/plutil -lint dist/ReluxProxy.app/Contents/Info.plist`: exit 0.
- `/usr/libexec/PlistBuddy ... dist/ReluxProxy.app/Contents/Info.plist`: exit 0.
- `/usr/bin/lipo -archs dist/ReluxProxy.app/Contents/MacOS/ReluxProxy`: exit 0;
  `x86_64 arm64`.
- `/usr/bin/file dist/ReluxProxy.app/Contents/MacOS/ReluxProxy`: exit 0;
  universal Mach-O executable.
- `/usr/bin/codesign --verify --deep --strict --verbose=2 dist/ReluxProxy.app`:
  exit 0.
- `/usr/bin/codesign -dv --verbose=4 dist/ReluxProxy.app`: exit 0;
  `Signature=adhoc`.
- `git diff --check -- README.md Tests/...`: exit 0.

### Repaired red gates

- First `swift test --filter TunnelRuntimeTests`: exit 1. The parameterized
  test exposed a private helper type; its visibility was corrected, then the
  exact command passed with exit 0.
- First `make lint`: exit 2. One new assertion exceeded the strict line-length
  rule; it was wrapped, then the exact command passed with exit 0.
- First executable-bit probe `/usr/bin/test -x ...`: exit 127 because macOS
  provides the executable at `/bin/test`. The corrected `/bin/test -x ...`
  probe passed with exit 0.

The earlier baseline and intermediate coverage commands also exited 0. Their
results were superseded by the final post-edit coverage run above.

## Files added or extended by this tester run

- `Tests/ReluxProxyTests/TunnelRuntimeTests.swift`
- `Tests/ReluxProxyTests/PackagingAndUsageTests.swift`
- `Tests/ReluxProxyTests/TunnelConfigurationTests.swift`
- `README.md`

The checkout contained pre-existing uncommitted implementation and tests for
the story. Those changes were preserved and treated as the implementation under
test.
