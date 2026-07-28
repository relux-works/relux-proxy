## Reviewer verdict — round 4

**accepted → done**

The current implementation satisfies the v1 persisted multi-tunnel contract and the task acceptance criteria. The profile store writes one validated schema-v1 JSON payload with stable UUIDs, one-time legacy migration, blocking preservation for invalid payloads, and no legacy resurrection. The controller owns independent per-profile session snapshots, process handles, diagnostics, generation checks, readiness, local-port isolation, and orderly shutdown. SSH invocation uses /usr/bin/ssh, local-only 127.0.0.1 dynamic forwarding, hardened options, and optional separate -l account semantics without parsing SSH configuration.

SwiftUI review: profile rows use persisted UUID identity, per-row runtime objects remain outside view bodies, @State is view-owned/private, lifecycle/edit/remove controls are accessible, and the menu aggregate reflects disconnected, active, and failed states. Docs now use tracked, non-contradictory references.

Reviewer validation (all exit 0): make lint; make test (29 Swift Testing cases across 4 suites); make app; codesign --verify --deep --strict --verbose=2 dist/ReluxProxy.app; lipo -archs dist/ReluxProxy.app/Contents/MacOS/ReluxProxy (x86_64 arm64); scoped git diff --check; tracked documentation-target checks. The reviewer run has no active board goal.

Reviewed task scope: Sources/ReluxProxy/{MenuContentView,ReluxProxyApp,SSHCommandBuilder,TunnelConfiguration,TunnelController,TunnelProfile,TunnelProfileStore,TunnelRuntime}.swift; Tests/ReluxProxyTests/{TunnelConfigurationTests,LocalPortProbeTests,TunnelControllerTests,TunnelProfileStoreTests}.swift; README.md; docs/current-state.md; CONTRIBUTING.md; Makefile. Foreign .spec, historical board, planning, research, and configuration changes were inspected only and preserved.

No product code was modified by the reviewer.