# TASK-260728-2eggfg: research-remote-vpn-reachability-over-ssh

## Description
Research and, where controlled fixtures allow, reproduce why a Mac using Relux Proxy SSH dynamic forwarding cannot reach a private network or egress path available through a VPN on the remote SSH machine.

## Scope
Trace packet origin and routing for ssh -D direct-tcpip channels; determine remote sshd network namespace/user policy, VPN split/full routes, firewall, DNS/search domains, and app SOCKS behavior; compare IP and hostname tests; evaluate current-product configuration versus sshuttle, tun2socks/Network Extension, and ssh -w. Use only safe read-only diagnostics and synthetic/authorized destinations. Produce a decision tree, commands, option matrix, recommendation, and follow-up board tasks if implementation is needed. Do not modify production Swift or remote VPN configuration.

## Acceptance Criteria
1. Evidence shows exactly where traffic and DNS originate for OpenSSH dynamic forwarding and under which conditions remote VPN routes are used. 2. The runbook tests remote direct reachability from an SSH session, local SOCKS IP reachability, SOCKS5h hostname resolution, route table/interface, resolver, firewall, and per-user/per-process VPN exclusions without exposing secrets. 3. Failure signatures distinguish no remote route, DNS-only failure, SOCKS-unaware client, UDP-dependent protocol, VPN policy/firewall denial, and system-routing expectations. 4. A comparison covers TCP, UDP, DNS, root/admin needs, remote sshd changes, Network Extension entitlements, distribution impact, and security for each candidate. 5. The result recommends either concrete v0.2.0 usage/product changes or a separately scoped implementation with acceptance tests.
