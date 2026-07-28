# Reviewer verdict

**Branch:** accepted -> done
**Role:** reviewer
**Date:** 2026-07-28

## Verdict

Accepted. The research answers every acceptance criterion and fits the existing Relux application-SOCKS architecture. The present fix is SOCKS5 with proxy-side DNS or SOCKS5h for SOCKS-aware TCP clients. A TUN, sshuttle, or Network Extension is a separate solution only for system-wide or SOCKS-unaware traffic, UDP, ICMP, or arbitrary IP routing.

## Independent evidence

- Outcome integrity: the two board outcomes are byte-identical to their `.research` source files. The main artifact contains all 11 required sections, five valid local links, balanced fences, no trailing whitespace, and both zsh command blocks parse with `zsh -n`.
- Privacy: the artifact pair contains no non-loopback IPv4 literal and no private-key, certificate, inline OpenVPN secret, or credential-file marker. No private endpoint was contacted during review.
- Concrete host: Tunnelblick 8.0.3 build 6303 is installed; one protected wb-vpn package exists; its config is `root:wheel` mode `0700` and unreadable to the reviewer. One root wb-vpn OpenVPN 2.6.21 process using OpenSSL 3.0.21 is active.
- VPN routing: the current log identifies only `utun11`, one completed initialization, seven pushed IPv4 routes representing four unique prefixes, two pushed DNS addresses, no redirect-gateway, and no pushed domain. Correct forced-host lookups passed 4/4 for the unique prefixes and 2/2 for DNS, all selecting `utun11`; no checked route carried `IFSCOPE`. The interface has one IPv4 address, no IPv6 address, and MTU 1400.
- Scoped DNS: both pushed DNS addresses occur together in one default resolver block and one `en0`-scoped block, and both route through `utun11`. The artifact correctly requires SOCKS5h or equivalent for private names and a canonical FQDN when no private search suffix is pushed.
- SSH policy and behavior: two readable sshd documents contain one Include, no Match block, and no explicit `AllowTcpForwarding`, `DisableForwarding`, or `PermitOpen`. Two current-user authorized keys contain no `restrict`, `no-port-forwarding`, or `permitopen` option. Independent loopback authentication, dynamic SOCKS readiness, numeric SOCKS connection, and proxy-resolved hostname connection all exited 0. This supports the precise conclusion that `direct-tcpip` opens a fresh server-side TCP socket and receives the live macOS route lookup; it does not inherit a frozen route table.
- Architecture: `Sources/ReluxProxy/SSHCommandBuilder.swift` constructs `/usr/bin/ssh -N -C -D` and `TunnelConfiguration.swift` binds `127.0.0.1`. README and current-state documentation explicitly define Relux as a TCP application SOCKS proxy, not a system VPN. The recommendation preserves that boundary.
- Tests: `swift test` completed successfully with 56 tests in 10 suites and zero failures.
- Source fact check: primary sources independently support the material claims: OpenSSH 10.2p1 `serverloop.c` and `channels.c` for `direct-tcpip`, policy checks, `getaddrinfo`, socket creation, and `connect`; OpenBSD `ssh(1)` and `sshd_config(5)` for dynamic SOCKS and forwarding policy; curl documentation for `socks5` versus `socks5h`; OpenVPN 2.6 documentation for pushed routes and DNS hooks; Tunnelblick documentation for DNS scripts and current stable 8.0.3 build 6303; Apple `connect(2)` for stream connection behavior; and the local macOS `netstat(1)` manual for `RTF_IFSCOPE`.

## Limitations reviewed

The protected static profile, privileged PF state, another Relux login account, and an exact private endpoint were not available. These are accurately disclosed and do not invalidate the current routing or SSH mechanics. One authorized numeric destination and TCP port, plus an optional canonical private FQDN and nonsecret health path, remain necessary only for endpoint-specific proof. No scan or configuration change is warranted.

## Review result

No material defect, architecture mismatch, privacy leak, or unaddressed acceptance criterion was found.