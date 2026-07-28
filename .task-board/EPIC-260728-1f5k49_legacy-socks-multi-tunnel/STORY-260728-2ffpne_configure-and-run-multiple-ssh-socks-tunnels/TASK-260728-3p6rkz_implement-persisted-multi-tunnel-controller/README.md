# TASK-260728-3p6rkz: implement-persisted-multi-tunnel-controller

## Description
Replace the single global tunnel form/process with persisted stable profiles and independent runtime sessions so multiple SSH SOCKS tunnels can run concurrently on different local ports.

## Scope
Add a versioned profile store with legacy migration; stable UUID identity; independent per-profile status/process/diagnostic state; duplicate-port and OS-port checks; local-only dynamic forwarding; aggregate menu-bar status; SwiftUI list/editor UI with add/remove/connect/disconnect; safe shutdown; unit tests; README/current-state usage updates. Use system /usr/bin/ssh and do not parse or rewrite ~/.ssh/config.

## Acceptance Criteria
1. A clean install can create, edit, persist, and relaunch multiple profiles, while an existing install migrates its current host/account/port exactly once. 2. Empty account produces target=host-or-alias and non-empty account produces account@host-or-alias; SSH arguments retain hardened options and 127.0.0.1 binding. 3. At least two sessions can be connecting/connected concurrently with separate Process, stderr, readiness, stop, and failure state. 4. Duplicate configured ports and already-bound OS ports are rejected without disturbing other sessions; active profiles cannot be edited or removed. 5. App termination stops every child process; menu icon and rows accurately summarize zero, some, and failed connections. 6. Tests cover persistence migration, command arguments, cross-profile port conflicts, independent lifecycle, and shutdown, and make test plus make app pass.
