# STORY-260728-2ffpne: configure-and-run-multiple-ssh-socks-tunnels

## Description
Provide one coherent macOS menu-bar journey for defining, persisting, connecting, observing, and disconnecting multiple SSH dynamic SOCKS5 tunnels.

## Scope
Profile contract and migration; independent runtime sessions; unique-port validation; menu-bar list/editor controls; aggregate status; shutdown safety; user documentation; macOS bundle validation; and publication of accepted v0.2.0 assets to the confirmed Relux GitLab project. Each connection continues to call /usr/bin/ssh and binds only 127.0.0.1.

## Acceptance Criteria
1. Persisted profiles have stable identity, an optional display name, SSH host or config alias, optional account override, and local SOCKS port. 2. Legacy sshHost, sshAccount, and localPort defaults migrate once into the new store. 3. Every row has independent validation, status, diagnostics, connect/disconnect, edit, and removal controls; active rows cannot be edited or removed unsafely. 4. Multiple independent ssh processes can remain connected simultaneously on different ports and all stop on app termination. 5. Unit tests, Swift package build, application packaging, documentation, and focused concurrency/lifecycle validation pass. 6. The accepted v0.2.0 commit is released through the confirmed Relux GitLab project with signed/notarized DMG assets and verified checksums, or the missing external release prerequisite is recorded exactly.
