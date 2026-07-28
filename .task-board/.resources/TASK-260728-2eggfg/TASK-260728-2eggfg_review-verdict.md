# Reviewer verdict: accepted

**Task:** `TASK-260728-2eggfg`  
**Review date:** 2026-07-28  
**Verdict branch:** `accepted` → `done`

## Outcome

The submitted research satisfies the task description, all five acceptance
criteria, and the research-specific definition of done. It correctly explains
that Relux Proxy's current `ssh -D` transport is a loopback application SOCKS
proxy rather than system routing, identifies the remote authenticated
`sshd-session` process as the owner of each destination TCP connection, and
separates numeric-IP, local-DNS, and proxy-DNS behavior.

The redacted two-Mac runbook is safe and actionable. Its decision tree
distinguishes:

- missing or excluded remote VPN routes;
- remote/private DNS and address-family failures;
- SOCKS-unaware clients and local-resolution mistakes;
- unsupported UDP, QUIC, ICMP, and system-routing expectations;
- SSH forwarding policy, per-user/per-process VPN policy, endpoint-filter, and
  destination-firewall denials.

The option matrix covers current application SOCKS configuration, macOS
network-service SOCKS settings, sshuttle, standalone tun2socks, Network
Extension plus tun2socks, and `ssh -w`, including TCP, UDP/ICMP, DNS,
privilege/admin requirements, remote changes, Apple entitlement/distribution
impact, and security fit.

The recommendation fits the repository architecture: keep v0.2.0 on the
existing loopback, TCP-only application-SOCKS contract; document SOCKS5h and the
system-routing boundary; leave packet-tunnel behavior to the separately gated
`NEPacketTunnelProvider` architecture. The follow-up
`TASK-260728-3rs1x2` has concrete scope and acceptance tests for the v0.2.0
guidance.

## Acceptance-criteria evidence

1. **Traffic and DNS origin:** The artifact traces SOCKS `CONNECT` to SSH
   `direct-tcpip`, the server-side `getaddrinfo`/`connect` path, remote route and
   source-address selection, and the client-controlled distinction between
   numeric IP, locally resolved SOCKS5, and proxy-resolved SOCKS5h.
2. **Safe diagnostics:** It supplies redacted commands for remote direct TCP,
   local SOCKS IP, SOCKS5h hostname, local-resolution comparison, route,
   interface, resolver, effective `sshd` policy, PF/system-extension inspection,
   and vendor per-user/per-process policy review. It limits tests to
   synthetic/authorized destinations and explicitly excludes secrets and
   configuration changes.
3. **Failure signatures:** The decision tree and signature table cover every
   requested failure class and identify the next discriminating check.
4. **Candidate comparison:** The matrix contains every requested protocol,
   privilege, server, entitlement, distribution, and security dimension.
5. **Action:** It recommends concrete v0.2.0 product/help changes and records
   the separately scoped implementation task `TASK-260728-3rs1x2` with
   acceptance tests.

## Independent validation

- Re-ran the loopback-only fixture:
  `.temp/TASK-260728-2eggfg/fixture/run_fixture.zsh` exited `0`.
- Numeric SOCKS and SOCKS5h requests returned `fixture-ok`.
- The deliberate local-resolution branch returned curl exit `97`, as asserted,
  because `::1` reached an IPv4-only service.
- The UDP-associate probe was rejected without a success reply.
- `lsof` showed the destination-side established socket owned by the
  authenticated user process `sshd-sess`.
- Server logs showed `direct-tcpip` targets for `127.0.0.1`, `localhost`, and
  `::1`; client logs showed `only socks5 connect supported`.
- `make test` passed all 22 Swift tests in 4 suites.
- `make lint` passed strict recursive Swift formatting checks.
- No production code, routes, resolver, PF, SSH server, or VPN configuration
  was modified by the reviewer.

## Source fact-check

The central claims were independently checked against authoritative sources:

- OpenSSH `ssh(1)` dynamic-forward semantics:
  https://man.openbsd.org/ssh#-D
- SSH `direct-tcpip` protocol fields and recipient-side connection:
  https://www.rfc-editor.org/rfc/rfc4254#section-7.2
- OpenSSH 10.2p1 server dispatch, resolver/connect path, privilege drop, and
  CONNECT-only parser:
  https://github.com/openssh/openssh-portable/blob/V_10_2_P1/serverloop.c#L415-L447
  https://github.com/openssh/openssh-portable/blob/V_10_2_P1/channels.c#L1668-L1688
  https://github.com/openssh/openssh-portable/blob/V_10_2_P1/channels.c#L4668-L4784
  https://github.com/openssh/openssh-portable/blob/V_10_2_P1/sshd-session.c#L443-L445
- Apple VPN routing and supported packet-tunnel/PF boundaries:
  https://developer.apple.com/documentation/networkextension/routing-your-vpn-network-traffic
  https://developer.apple.com/documentation/networkextension/nepackettunnelprovider
  https://developer.apple.com/documentation/technotes/tn3165-packet-filter-is-not-api
- sshuttle's current macOS PF, TCP/DNS, privilege, and remote-Python behavior:
  https://sshuttle.readthedocs.io/en/latest/requirements.html
  https://sshuttle.readthedocs.io/en/latest/manpage.html

The local temporary OpenSSH checkout is a shallow `master` snapshot rather than
the tagged revision. This is non-blocking because the submitted document cites
immutable `V_10_2_P1` URLs and the reviewer fetched that tag directly for the
source check; future archived source bundles should record the exact tag commit
to avoid ambiguity.

## Final reviewer finding

No acceptance-blocking factual error, missing requested diagnostic, unsafe
instruction, architecture mismatch, or test regression was found. Acceptance
is warranted.
