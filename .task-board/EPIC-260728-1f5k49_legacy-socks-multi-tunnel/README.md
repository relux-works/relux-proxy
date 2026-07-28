# EPIC-260728-1f5k49: legacy-socks-multi-tunnel

## Description
Evolve the shipped macOS menu-bar SOCKS application into a reliable multi-tunnel controller while continuing to use system OpenSSH and remaining separate from the future system VPN architecture.

## Scope
Persist and manage multiple local-only SOCKS5 tunnels backed by independent system ssh processes. Support IP addresses, hostnames, and aliases from ~/.ssh/config; optional account override; explicit unique local ports; migration of existing settings; independent lifecycle; build and release-path validation. Excludes Network Extension, iOS, UDP forwarding, remote relay, automatic system proxy changes, and changes to user SSH keys or config.

## Acceptance Criteria
1. A user can create and persist at least two tunnel profiles, each with a target and unique local SOCKS port. 2. A target may be an IP address, hostname, or OpenSSH Host alias, and leaving account override empty preserves User, IdentityFile, Port, ProxyJump, HostName, and related resolution from ~/.ssh/config. 3. Two or more profiles can be connected concurrently and controlled independently without one process or failure changing another. 4. Port conflicts, invalid input, startup failure, termination, removal, and application quit are safe and visible. 5. Existing single-profile settings migrate without loss and the macOS application build plus automated tests pass.
