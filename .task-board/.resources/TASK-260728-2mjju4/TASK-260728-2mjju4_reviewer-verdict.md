# TASK-260728-2mjju4 reviewer verdict

Date: 2026-07-28
Role: reviewer
Verdict: accepted

## Review conclusion

The current working-tree implementation satisfies the task acceptance criteria
and the version 1.0 legacy SOCKS multi-tunnel contract. No implementation
regression, architecture mismatch, or stop-the-line condition was found.

The authorized external-host identity check remains a documented physical Mac
step because this run was not given two external SSH hosts or an authorized
exit-identity endpoint. The deterministic local evidence covers all behavior
that can be validated safely without those credentials or hosts.

## Independent evidence

### Concurrent lifecycle and isolation

- `swift test --filter TunnelControllerTests`: exit 0; 10 tests passed.
- The concurrent-session test starts independent handles for profiles on
  `127.0.0.1:1080` and `127.0.0.1:1081`, marks both connected, fails the
  second, and proves the first remains connected and running.
- Stopping the first preserves the second profile's failure and diagnostic.
- Additional tests pass for occupied-port isolation, readiness-timeout cleanup,
  stale callbacks, active edit/removal rejection, coordinated two-child
  shutdown, forced stop, and disconnected relaunch state.

### SSH argv and alias/account semantics

- Exact static argv uses `/usr/bin/ssh` with separate array elements, including
  `-D 127.0.0.1:<port>`, optional `-l <account>`, and the unchanged destination.
- Parameterized tests pass for `203.0.113.10`, `bastion.example.net`, and
  `work-bastion`; shell metacharacters remain literal arguments and no shell or
  `-c` invocation is constructed.
- A controlled, non-networking `/usr/bin/ssh -G` fixture independently proved:
  the bare `work-bastion` alias resolves `HostName=203.0.113.10`,
  `Port=2222`, `User=config-user`; adding `-l ops` retains that hostname and
  port while changing only `User` to `ops`. Numeric IP and DNS hostname
  projections likewise retain the destination and use `User=ops`.

### Persistence, conflicts, diagnostics, and shutdown

- Focused configuration/store/runtime/packaging selection: exit 0; 31 tests
  passed across 5 suites.
- The store matrix passes clean/legacy/idempotent migration, incompatible
  legacy input, payload preservation, stable IDs, duplicate-port rejection,
  persistence/relaunch, and deleted-profile non-resurrection.
- A real loopback socket fixture passes occupied-port detection.
- Runtime tests pass direct executable/argument launch, stderr/termination,
  independent process handles, readiness ready/timeout/cancellation, and
  scheduler cancellation.

### Full gates and coverage

- `make lint`: exit 0.
- `make test`: exit 0; 44 tests in 7 Swift Testing suites passed.
- `swift test --enable-code-coverage`: exit 0; 44 tests passed.
- Affected non-UI tunnel files: 1,106 of 1,202 lines covered, **92.01%**.
  Whole executable coverage is 54.62% because the SwiftUI view and app-entry
  bodies are outside the unit/local integration harness.
- `git diff --check` over the app, tests, build files, and usage docs: exit 0.

### Packaged application

- `SIGN_IDENTITY=- make app`: exit 0. Ad-hoc signing was selected explicitly to
  remain inside the no-release-signing/notarization boundary.
- `dist/ReluxProxy.app` contains:
  `Contents/MacOS/ReluxProxy`, `Contents/Info.plist`,
  `Contents/Resources/ReluxProxy.icns`, and `_CodeSignature/CodeResources`.
- The executable bit is set; plist lint passes.
- Plist values: `CFBundleExecutable=ReluxProxy`,
  `CFBundleIdentifier=works.relux.proxy`, `CFBundlePackageType=APPL`,
  `LSMinimumSystemVersion=14.0`, and `LSUIElement=true`.
- The executable is a universal `x86_64 arm64` Mach-O.
- `codesign --verify --deep --strict` passes and reports an ad-hoc signature.

### Installed-Mac procedure

`README.md` tells an operator to copy the app to Applications, create and
connect two profiles with distinct ports, configure SOCKS-aware clients for
`127.0.0.1:<saved-port>`, query an authorized HTTPS exit-identity endpoint via
each port with `curl --socks5-hostname`, disconnect one profile, and confirm the
remaining tunnel and identity are unchanged.

## Architecture fit

The implementation follows the project contract directly:

- one versioned profile store and one-time legacy migration;
- runtime registry keyed by stable profile UUID;
- one immutable configuration snapshot, process handle, diagnostic buffer, and
  generation token per session;
- system OpenSSH remains the configuration/alias authority;
- loopback-only SOCKS endpoints and no system proxy/VPN behavior;
- no persisted runtime state or automatic reconnect;
- normal quit terminates only child handles owned by this app run.

## Evidence files

Task-scoped command logs are retained under:
`.temp/TASK-260728-2mjju4/reviewer/`.

Key files are `focused-controller-tests.log`,
`focused-contract-persistence-runtime-tests.log`, `make-lint.log`,
`make-test.log`, `swift-test-coverage.log`, `coverage-report.log`,
`make-app-adhoc.log`, `bundle-inspection.log`, and `ssh-resolution.log`.

The implementation and validation scope is currently uncommitted. This reviewer
did not stage, commit, or supply `commit_ack`; the commit-owning mover remains
responsible for committing its scope before any commit-confirmed parent
completion transition.
