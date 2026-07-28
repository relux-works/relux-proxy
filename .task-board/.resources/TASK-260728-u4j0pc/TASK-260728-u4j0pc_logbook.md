# TASK-260728-u4j0pc research logbook

**Date:** 2026-07-28
**Scope boundary:** read-only, privacy-redacted host inspection and loopback-only tests; no private endpoint contacted and no system or VPN configuration changed

## Findings and decisions

- **Active profile:** Tunnelblick 8.0.3 is running wb-vpn through root OpenVPN 2.6.21. The protected shared profile was located without reading its raw contents.
- **Current interface:** the wb-vpn OpenVPN log names only `utun11`. The identifier is a current-session value, not a stable configuration property.
- **Route model:** wb-vpn is a split tunnel with four unique pushed IPv4 prefixes and no pushed default or IPv6 route. Forced-host route lookup for every unique prefix selected `utun11`.
- **Route scope:** the live wb-vpn routes are not marked `RTF_IFSCOPE`. An authenticated `sshd` worker therefore uses them through ordinary connect-time system route selection.
- **DNS model:** two private DNS servers are pushed, installed in the default macOS resolver, and themselves routed through `utun11`. No private domain/search suffix is pushed.
- **SSH model:** current global configuration and current-user key options do not restrict forwarding. Loopback numeric and proxy-DNS `direct-tcpip` probes succeeded.
- **Decision:** recommend the existing Relux SOCKS5 path with proxy DNS/SOCKS5h for SOCKS-aware TCP applications. Do not introduce source routes, forwarding/NAT, PF, sshuttle, TUN, or Network Extension work for this case.
- **Escalation boundary:** a packet tunnel is a separate requirement for SOCKS-unaware/system-wide applications, UDP/QUIC without TCP fallback, ICMP, or arbitrary IP routing.

## Anomalies

- The VPN server pushes the same RFC1918 `/8`, `/14`, and `/18` routes twice. The log records `File exists` noise, but the four unique final routes are installed and usable. This should be cleaned up server-side when convenient; it is not the present blocker.
- An initial `route -n get` gate passed network-form destinations without `-host` and exited `1` overall because two network-base queries selected `en0`. The result was kept red. Correct forced-host lookups and independent inside-prefix lookups exited `0` and selected `utun11`.
- The root-only profile parser exited `1`; non-interactive sudo also exited `1` because a password is required. No attempt was made to bypass the protection.
- `sshd -T` exited `1` for the non-root researcher because protected host keys were unavailable. Direct config/key-option inspection plus functional loopback forwarding supplied the fallback evidence.
- PF status inspection exited `1` for lack of administrator privilege. The macOS Application Firewall is disabled, and loopback forwarding works, but target-specific PF/content-filter policy remains unverified.

## Remaining environment fact

One explicitly authorized destination is needed only for end-to-end proof:
a numeric address, TCP port, optional canonical private FQDN, and optional
nonsecret health path. No scan, full route/DNS dump, packet capture, or secret
material is required.

## Scope integrity

The pre-existing dirty worktree was preserved. This task adds only its
`.research` artifacts, task-scoped board outcome, notes/checklist updates, and
normal task-board lifecycle records.
