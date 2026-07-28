# TASK-260728-2eggfg research logbook

**Date:** 2026-07-28  
**Scope boundary:** research and read-only/synthetic diagnostics only; no production Swift, route, resolver, PF, SSH server, or VPN configuration changes

## Findings and decisions

- **Remote traffic origin:** OpenSSH `-D` converts a local SOCKS `CONNECT` into a `direct-tcpip` channel. The authenticated remote `sshd` worker performs `getaddrinfo` and opens the destination TCP socket. The remote route/VPN and destination firewall therefore see a remote-originated connection.
- **Policy caveat:** a successful command in an interactive remote shell is necessary but can be insufficient when the VPN or endpoint filter is scoped per app, process, or user. The forwarding worker must be eligible independently.
- **DNS split:** numeric destinations require no destination lookup; ordinary SOCKS5 can resolve on the source Mac; SOCKS5h/proxy DNS preserves the hostname for remote resolution. Relux does not install remote search domains on the source Mac.
- **Protocol boundary:** OpenSSH dynamic forwarding implements SOCKS `CONNECT` only. It does not provide UDP association, ICMP, arbitrary IP routing, or guaranteed QUIC support.
- **Product decision:** preserve the loopback application-SOCKS contract for v0.2.0 and make its TCP/DNS/system-routing boundary explicit. Do not add PF, system proxy, routes, `sshuttle`, standalone tun2socks, or `ssh -w` as an implicit product behavior.
- **Follow-up:** created `TASK-260728-3rs1x2` for user-facing SOCKS/VPN reachability guidance and tests. System-wide routing remains the separately gated Network Extension product.

## Controlled-fixture anomalies

- The first fixture run exited `97` because curl's local SOCKS resolution selected IPv6 `::1` while the synthetic service listened only on IPv4. This was retained as an expected-red DNS/address-family signature rather than relabeled as a pass.
- SOCKS5h preserved `localhost`; the remote resolver tried `::1` and then `127.0.0.1`, and the connection succeeded.
- A SOCKS5 UDP-associate probe was rejected, matching pinned OpenSSH 10.2p1 source.
- The loopback service connection was owned on its outbound side by the authenticated `sshd-sess` process.
- The macOS 26.5 fixture had no matching `/dev/tun*` or `/dev/utun*` device node. This is fixture evidence against stock `ssh -w` portability, not a claim that third-party TUN implementations cannot exist.

## Unresolved environment facts

No real VPN/vendor policy or private target was probed. The environment owner must still determine, using the redacted runbook:

- whether the target prefix/address family is included in the remote VPN;
- whether the authenticated `sshd` worker/account is admitted by per-app/per-process/per-user policy;
- whether private DNS applies to that process;
- whether an endpoint filter or destination firewall denies the flow.

## Scope integrity

The pre-existing dirty worktree was preserved. Research added only `.research` artifacts and board-managed notes/resources/tasks; production source and remote/system configuration were not modified.
