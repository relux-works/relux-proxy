## Round 4 rework

Resolved the reviewer documentation-integrity finding without touching the foreign `.spec/legacy-socks-multi-tunnel.md`. README now points shipped multi-profile behavior to tracked `docs/current-state.md` and distinguishes the tracked future-VPN specification index. Current-state now points its workflow to the tracked README and describes the implementation directly.

Validation (all exit 0): `make lint`; `make test` (29 Swift Testing tests across 4 suites); `make app` (universal signed app); `git diff --check`; stale-link scan; tracked-link target checks.

Scoped task files remain: Makefile; README.md; docs/current-state.md; Sources/ReluxProxy/{MenuContentView,ReluxProxyApp,SSHCommandBuilder,TunnelConfiguration,TunnelController,TunnelProfile,TunnelProfileStore,TunnelRuntime}.swift; Tests/ReluxProxyTests/{TunnelConfigurationTests,LocalPortProbeTests,TunnelControllerTests,TunnelProfileStoreTests}.swift. Foreign `.spec`, historical board, and config worktree changes were preserved.