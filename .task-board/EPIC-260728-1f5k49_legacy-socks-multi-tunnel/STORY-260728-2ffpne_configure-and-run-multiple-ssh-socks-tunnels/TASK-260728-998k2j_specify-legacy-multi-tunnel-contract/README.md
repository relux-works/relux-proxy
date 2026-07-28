# TASK-260728-998k2j: specify-legacy-multi-tunnel-contract

## Description
Write the focused source-of-truth contract for extending the current macOS SOCKS product, including profile persistence, OpenSSH alias semantics, migration, port ownership, concurrent lifecycle, diagnostics, and explicit non-goals.

## Scope
Create .spec/legacy-socks-multi-tunnel.md and align README/current-state wording where required. Define that an empty account field delegates User to ~/.ssh/config while a non-empty value is an explicit command-line override. Preserve local-only 127.0.0.1 binding and system ssh behavior. No production Swift changes.

## Acceptance Criteria
1. The specification defines persisted schema and one-time migration from sshHost/sshAccount/localPort. 2. IP, hostname, and Host alias behavior is unambiguous, including account override precedence and inheritance of IdentityFile, Port, ProxyJump, HostName, and host-key policy. 3. Duplicate ports, editing/removal while active, failure isolation, app quit, diagnostics bounds, and restart behavior have deterministic requirements. 4. Automatic reconnect, system proxy mutation, VPN/Network Extension, SSH config editing, key import, and non-loopback exposure are explicitly out of scope. 5. Documentation remains consistent with the shipped SOCKS product and future VPN boundary.
