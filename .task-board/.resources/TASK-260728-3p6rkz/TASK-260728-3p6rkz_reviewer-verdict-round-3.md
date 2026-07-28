# TASK-260728-3p6rkz reviewer verdict — round 3

## Verdict

**changes_requested → `to-dev`**

The third rework correctly fixes failed-readiness cleanup. Failed status and diagnostics now survive lifecycle actions, process termination, and quit-time cleanup until an explicit retry; the new generation and stale-callback assertions pass. Persistence, command construction, concurrent sessions, port isolation, UI state ownership, accessibility controls, and shutdown behavior otherwise match the accepted contract.

## Required finding

### Required docs depend on a foreign untracked and contradictory spec

The updated `README.md:75` and `docs/current-state.md:69` link to `.spec/legacy-socks-multi-tunnel.md`. Read-only repository evidence shows that path as `??` and `git cat-file -e HEAD:.spec/legacy-socks-multi-tunnel.md` exits 128 because it is absent from `HEAD`. The worktree-safety contract and every producer handoff classify `.spec` changes as foreign and exclude this file from the task scope, so the commit-owning mover cannot include it with this task. A scoped delivery would publish broken links. The foreign file also still says that the current release is a one-tunnel application and that multi-tunnel support has not shipped, contradicting the updated docs that call the contract implemented.

Required rework: keep edits limited to task-scoped documentation. Remove these two links or replace them with a tracked, non-contradictory destination already in the authorized scope. Do not modify, stage, or commit the foreign `.spec` file. Add a deterministic tracked-target check for the final link destination, rerun the strict gates, and list the same scoped source, test, build, and doc files in the next outcome.

## Reviewer validation

- `make lint` — exit 0.
- `make test` — exit 0; 29 tests in 4 suites.
- `make app` — exit 0; universal application build.
- `codesign --verify --deep --strict --verbose=2 dist/ReluxProxy.app` — exit 0.
- `lipo -archs dist/ReluxProxy.app/Contents/MacOS/ReluxProxy` — exit 0; `x86_64 arm64`.
- Scoped `git diff --check` — exit 0.
- Reviewer run goal query — no active child goal.

## Reviewed task scope

Source: `MenuContentView.swift`, `ReluxProxyApp.swift`, `SSHCommandBuilder.swift`, `TunnelConfiguration.swift`, `TunnelController.swift`, `TunnelProfile.swift`, `TunnelProfileStore.swift`, `TunnelRuntime.swift`.

Tests: `LocalPortProbeTests.swift`, `TunnelConfigurationTests.swift`, `TunnelControllerTests.swift`, `TunnelProfileStoreTests.swift`.

Documentation and build: `README.md`, `CONTRIBUTING.md`, `docs/current-state.md`, `Makefile`.

The reviewer modified no product code and preserved all foreign worktree changes.