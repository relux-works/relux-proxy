# TASK-260728-3rs1x2: add-socks-vpn-reachability-guidance

## Description
Clarify the v0.2.0 Relux Proxy contract and provide privacy-safe guidance for reaching remote VPN destinations through the existing OpenSSH dynamic forward.

## Scope
Update user-facing tunnel copy, Help or README guidance, and tests. Label the endpoint as an application SOCKS5 proxy that carries TCP only and is not a system VPN. Explain proxy-side DNS for private names and the requirement that the remote VPN route and policy include the sshd forwarding process. Do not modify system proxy settings, PF, routes, Network Extension, sshd, or remote VPN configuration.

## Acceptance Criteria
1. UI or Help labels the endpoint as application SOCKS5, TCP-only, and not system-wide routing. 2. Guidance distinguishes SOCKS5 local DNS from SOCKS5h or proxy DNS and provides redacted IP and hostname checks. 3. Guidance identifies remote route, sshd process policy, firewall, SOCKS-unaware app, and UDP limitations. 4. Tests cover the new copy or Help content and confirm tunnel launch semantics remain unchanged. 5. README and current-state documentation agree with the product behavior.
