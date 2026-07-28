# TASK-260728-u4j0pc: investigate-tunnelblick-wb-vpn-through-ssh-socks

## Description
Investigate the concrete macOS Tunnelblick profile wb-vpn and determine how another machine connected over SSH dynamic SOCKS forwarding can reach the private VPN networks routed on this Mac.

## Scope
Use read-only and privacy-redacted diagnostics on the current Mac first: Tunnelblick/OpenVPN process state, active utun interfaces, route table, scoped DNS and profile directives relevant to routing/DNS. Reproduce only safe loopback or explicitly authorized connectivity; do not print profile secrets, certificates, keys, credentials, full private IPs, or scan networks. Distinguish application SOCKS from system-wide routing and specify the exact configuration/test sequence needed for remote clients.

## Acceptance Criteria
Evidence identifies the active Tunnelblick interface and whether wb-vpn installs system routes usable by sshd child sockets; determines proxy-side DNS requirements and any Tunnelblick/OpenVPN/firewall/server-policy blockers; provides privacy-safe commands to prove numeric-IP and hostname reachability through ssh -D; states whether current SOCKS design is sufficient or whether sshuttle/TUN/Network Extension is required; records remaining endpoint-specific input only if an authorized destination is indispensable.
