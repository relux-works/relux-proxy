# STORY-260728-d17qre: reach-remote-vpn-networks-through-ssh

## Description
Determine why clients using an SSH tunnel cannot reach networks available through a VPN on the remote SSH host, and select the smallest safe Relux Proxy product path that provides the intended reachability.

## Scope
Analyze OpenSSH dynamic forwarding data plane, remote VPN routing and policy, DNS placement, SOCKS-aware versus arbitrary applications, macOS Network Extension/tun2socks options, sshuttle, and SSH tun devices. Produce deterministic diagnostics and a recommendation. No production routing implementation until evidence selects the required layer.

## Acceptance Criteria
1. The research distinguishes remote VPN egress/public-IP use from access to private VPN subnets and distinguishes SOCKS-aware TCP apps from system-wide IP traffic. 2. A reproducible diagnostic matrix identifies whether sshd-launched connections see the VPN route, resolver, firewall, and policy on the remote host. 3. The result explains SOCKS5/SOCKS5h DNS behavior and tests direct IP plus hostname access through the local proxy. 4. Options including current ssh -D, proxy-aware clients, sshuttle, tun2socks/Network Extension, and ssh -w are compared for TCP/UDP/DNS, privileges, macOS packaging, remote configuration, and security. 5. The recommended v0.2.0-compatible action or a separate implementation story is explicit, with exact acceptance tests and no claim that SOCKS creates a system route.
