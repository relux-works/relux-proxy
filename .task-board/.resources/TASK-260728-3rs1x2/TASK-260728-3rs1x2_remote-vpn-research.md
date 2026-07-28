# Remote VPN reachability through OpenSSH dynamic forwarding

**Task:** `TASK-260728-2eggfg`  
**Date:** 2026-07-28  
**Role:** researcher  
**Scope:** Relux Proxy's current OpenSSH `-D` tunnel on macOS; read-only diagnostics and loopback-only synthetic reproduction  
**Evidence labels:** **Observed** means reproduced on the controlled fixture, **Source-verified** means traced to primary documentation or pinned source, and **Environment-dependent** means the VPN vendor or administrator must verify it on the two Macs.

## Executive finding

Relux Proxy currently creates an **application SOCKS proxy**, not a system VPN:

```text
source application
  -> SOCKS5 on 127.0.0.1:<local-port> (source Mac)
  -> SSH direct-tcpip channel
  -> authenticated sshd worker resolves/connects (remote Mac)
  -> remote Mac route/VPN/firewall
  -> destination
```

The destination TCP socket originates on the remote SSH machine, in the authenticated server-side SSH process context. The source Mac does not acquire the remote Mac's routes, DNS configuration, or VPN interface. A remote VPN route is used only when all of these conditions hold:

1. The application on the source Mac actually uses the SOCKS endpoint.
2. The application requests a TCP `CONNECT`; OpenSSH dynamic forwarding does not implement SOCKS5 UDP association.
3. `sshd` and the active key/certificate policy permit the destination.
4. The remote resolver can resolve a private hostname when the application delegates DNS to SOCKS.
5. The remote route, per-app/per-process VPN policy, and firewall apply to the authenticated `sshd` forwarding worker.
6. The destination accepts the source address selected by the remote VPN/kernel.

**Key distinction:** a successful `curl` or `nc` in a remote interactive shell proves that a shell process can reach the destination. It does not conclusively prove that a per-app VPN or endpoint security policy admits the separate `sshd` forwarding process.

**Recommendation:** keep v0.2.0 within the current loopback SOCKS contract. Add explicit product/help copy stating “application SOCKS5 proxy, TCP only, not a system VPN,” explain SOCKS5h/proxy-side DNS, and link a redacted two-stage diagnostic. Do not silently add PF rules, system proxy settings, routes, `sshuttle`, `ssh -w`, or a Network Extension to this release. Follow-up implementation task: `TASK-260728-3rs1x2`.

## 1. What Relux Proxy currently does

The repository's current-state documentation and launcher construct the equivalent of:

```bash
/usr/bin/ssh -N -C -D 127.0.0.1:<local-port> <remote>
```

The explicit loopback bind is an important security boundary: only local processes can normally connect to the SOCKS listener. The app does not install an IP route, change the macOS resolver, enable a system SOCKS setting, create a tunnel interface, or start a Network Extension.

The planned legacy multi-tunnel behavior in [`.spec/legacy-socks-multi-tunnel.md`](../.spec/legacy-socks-multi-tunnel.md) retains this manual, application-level SOCKS model. The separate system VPN design in [`.spec/product.md`](../.spec/product.md) and the architecture documents uses `NEPacketTunnelProvider`; it is a different product surface with different entitlements, transport, DNS, UDP, security, and distribution requirements.

Consequences on the source Mac:

- A SOCKS-aware application can send supported TCP connections through the tunnel.
- An application that ignores the configured SOCKS proxy continues to use the source Mac's normal route.
- `ping`, arbitrary UDP, QUIC-only traffic, and ordinary system DNS are not tunneled by `ssh -D`.
- `route -n get <private-IP>` on the source Mac is expected to show its ordinary route; no private route is created by Relux Proxy.
- Setting a SOCKS proxy in one application does not make the remote VPN “system-wide” on the source Mac.

## 2. Exact packet, process, route, and DNS origin

### 2.1 TCP connection path

OpenSSH's documented `-D` behavior allocates a local dynamic-forward listener and treats it as a SOCKS4/5 server. For each accepted SOCKS `CONNECT`, the client opens an SSH `direct-tcpip` channel. The SSH Connection Protocol includes the requested destination host and port plus the client's originator address as channel metadata. The server then creates a new outbound TCP socket to the requested destination.

Pinned OpenSSH 10.2p1 source establishes the implementation details:

- The server parses `direct-tcpip`, checks forwarding policy, and calls the port-connect path in [`serverloop.c`](https://github.com/openssh/openssh-portable/blob/V_10_2_P1/serverloop.c#L415-L447).
- That path calls `getaddrinfo` and `connect` on the server in [`channels.c`](https://github.com/openssh/openssh-portable/blob/V_10_2_P1/channels.c#L4729-L4784).
- The authenticated server session drops to the login UID before serving the connection in [`sshd-session.c`](https://github.com/openssh/openssh-portable/blob/V_10_2_P1/sshd-session.c#L443-L445).

Therefore:

| Property | Origin or owner |
|---|---|
| SOCKS listener | Source Mac, Relux-launched `ssh`, bound to loopback |
| SSH transport | Source Mac to remote SSH server |
| Destination TCP socket | Authenticated server-side `sshd` worker on the remote Mac |
| Destination-visible source IP | Chosen by the remote kernel/VPN route for that socket |
| Destination route lookup | Remote host and applicable VPN policy |
| Ordinary source-Mac apps that ignore SOCKS | Source Mac route, not the SSH tunnel |

The originator address carried in `direct-tcpip` is protocol metadata; it does not make the outbound TCP packet retain the source Mac's IP. The remote destination sees the address selected for the remote socket, commonly a VPN interface address or a VPN-side translated address.

### 2.2 User, process, and network-policy context

On a normal macOS SSH server, the forwarding socket is opened by an authenticated, user-owned SSH session/worker. The controlled fixture observed an `sshd-sess` process owned by the test login UID holding the destination-side TCP connection.

This matters when VPN or security policy is scoped:

- A route-based, device-wide VPN whose included route covers the target will normally be eligible for the worker's socket.
- A per-app VPN or endpoint filter can include a terminal or browser while excluding `sshd`, or the reverse.
- A per-user rule can differ between the logged-in console user and the SSH account.
- A VPN client may deliberately bypass loopback, local LAN, selected processes, IPv6, or public egress while still showing “connected.”
- The destination firewall may admit only a particular VPN pool or identity even when the remote route is correct.

macOS does not expose Linux-style network namespaces as the normal host routing model. If the SSH server is instead inside a VM, container, or another operating system with namespaces, the relevant namespace is the one containing the server-side SSH worker. Entering a different namespace from an interactive shell does not move `direct-tcpip` sockets into it.

### 2.3 DNS decision matrix

SOCKS5 can carry either a numeric address or a domain name. The application and SOCKS client behavior decide where resolution occurs:

| Application request | DNS origin | What SSH sends | Expected implication |
|---|---|---|---|
| Numeric destination IP | None for the destination | Numeric IP | Isolates routing/TCP policy from destination DNS |
| Hostname with local-resolution mode, such as curl `--socks5` | Source Mac | Locally resolved IP | Private split DNS on the remote Mac is bypassed |
| Hostname with proxy-resolution mode, such as curl `--socks5-hostname` or `socks5h://` | Remote SSH machine | Domain name | Server-side OpenSSH calls the remote resolver |
| Application ignores SOCKS or uses its own DoH | Application-specific/source path | No applicable SOCKS request | Relux cannot redirect or resolve it |

curl documents the distinction: [`--socks5`](https://curl.se/docs/manpage.html#--socks5) resolves locally, while [`--socks5-hostname`](https://curl.se/docs/manpage.html#--socks5-hostname) delegates hostname resolution to the SOCKS proxy. In OpenSSH's dynamic forward, a delegated hostname is sent through `direct-tcpip`, and the remote server performs `getaddrinfo`.

Private search domains can therefore work through SOCKS5h when they are applicable to the server-side SSH process. Relux does not copy those domains into the source Mac's system resolver.

### 2.4 Protocol limits

RFC 1928 defines SOCKS5 `CONNECT`, `BIND`, and `UDP ASSOCIATE`, but a server is not required to implement every command. OpenSSH 10.2p1 accepts only `CONNECT` in its dynamic forwarding parser; its pinned source rejects other commands in [`channels.c`](https://github.com/openssh/openssh-portable/blob/V_10_2_P1/channels.c#L1684-L1688).

Current `ssh -D` therefore carries:

- TCP-based HTTP/1.1, HTTP/2, TLS, SSH, database connections, and other TCP protocols when the application supports SOCKS.

It does not carry:

- UDP DNS from the source system resolver;
- QUIC/HTTP/3 unless the application falls back to TCP;
- ICMP/ping;
- multicast/broadcast or arbitrary IP packets;
- a SOCKS5 UDP association.

An application can still use TCP-based name resolution through its proxy behavior, but that does not convert `ssh -D` into a UDP tunnel.

## 3. When the remote VPN route is and is not used

Apple's Network Extension route model distinguishes included routes, excluded routes, a default route, interface scoping, enforced routes, and per-app rules. See [Routing your VPN network traffic](https://developer.apple.com/documentation/networkextension/routing-your-vpn-network-traffic) and [`includeAllNetworks`](https://developer.apple.com/documentation/networkextension/nevpnprotocol/includeallnetworks).

The remote VPN route is expected to be used when:

- the destination IP is in an included route or the effective VPN default route;
- no more-specific exclusion or interface-scoped route wins;
- the VPN admits traffic owned by the `sshd` forwarding worker/login UID;
- the address family is carried by the VPN;
- an endpoint filter and remote firewall allow the flow.

The remote VPN route is not guaranteed merely because:

- the menu bar reports that the VPN is connected;
- a different application reaches the destination;
- a remote shell command reaches it under a process-specific rule;
- IPv4 works while the private hostname first returns an unreachable IPv6 address;
- private routes work but public egress intentionally remains local under split tunneling;
- the source Mac has a SOCKS configuration.

For public egress comparison, use only an organization-owned diagnostic endpoint. A public “what is my IP” service can disclose both machines' addresses to a third party and is unnecessary for this decision tree.

## 4. Safe, redacted diagnostic runbook for both Macs

### 4.1 Safety and evidence handling

Use an authorized synthetic service or a low-impact organization-owned health endpoint. Obtain its numeric IP, hostname, TCP port, address family, and expected response from the service owner. Run the sequence once for the private-network target and, when egress behavior is in question, again for an organization-owned public egress target.

Do not paste into tickets or logs:

- private keys, certificates, tokens, cookies, authorization headers, or request bodies;
- raw `authorized_keys` lines;
- complete private route tables, DNS search domains, VPN gateway addresses, usernames, device names, team IDs, or bundle IDs;
- packet captures from unrelated traffic.

Replace those fields with stable labels such as `<REMOTE_MAC>`, `<PRIVATE_V4>`, `<PRIVATE_HOST>`, `<VPN_IF>`, and `<SSH_USER>`. Preserve command exit codes and the relevant error phrase. Run optional `sudo` reads only with administrator authorization. Do not change routes, PF, system proxy settings, `sshd_config`, or VPN configuration during diagnosis.

Set placeholders independently in each shell:

```bash
TARGET_IP='<authorized-numeric-IP>'
TARGET_HOST='<authorized-hostname>'
TARGET_PORT='<authorized-TCP-port>'
SOCKS_PORT='<Relux-local-port>'
```

Use an explicit `http://` synthetic endpoint for the IP-versus-hostname curl comparison when possible. Testing an HTTPS service by raw IP can produce a certificate-name failure that is unrelated to routing.

### 4.2 Remote Mac B: prove direct destination reachability

First test the exact address family and TCP service from the SSH account:

```bash
/usr/bin/id -un
/usr/bin/nc -vz -G 5 "$TARGET_IP" "$TARGET_PORT"
/usr/bin/nc -vz -G 5 "$TARGET_HOST" "$TARGET_PORT"
```

Interpretation:

- IP and hostname both fail: start with remote route, VPN policy, firewall, and service availability.
- IP succeeds and hostname fails: remote DNS/search-domain or address-family issue.
- Both succeed: continue; this proves the shell context, not necessarily the forwarding worker context.

Inspect only the route and resolver data relevant to the synthetic target:

```bash
/sbin/route -n get "$TARGET_IP"
/usr/sbin/scutil --nwi
/usr/bin/dscacheutil -q host -a name "$TARGET_HOST"
/usr/sbin/scutil --dns
/usr/sbin/netstat -rn -f inet
/usr/sbin/netstat -rn -f inet6
```

Review locally, then record a redacted summary:

- selected interface for the target, represented as `<VPN_IF>` or `<NON_VPN_IF>`;
- whether the target prefix is included, excluded, or absent;
- IPv4/IPv6 answers and their ordering;
- whether the required search/match domain is present;
- whether the observed result differs by login user or source application.

If administrator access is authorized, derive the effective SSH forwarding policy without exposing key material:

```bash
sudo /usr/sbin/sshd -T \
  -C user='<SSH_USER>',host='<SOURCE_HOST>',addr='<SOURCE_IP>'
```

Inspect only `allowtcpforwarding`, `disableforwarding`, `permitopen`, and `permittunnel`. Also inspect the active account/key policy locally for `restrict`, `no-port-forwarding`, or `permitopen`, but never copy an `authorized_keys` line into the artifact. `Match` blocks and certificate options can change the effective result.

Optional authorized reads:

```bash
/usr/bin/systemextensionsctl list
sudo /sbin/pfctl -sr
```

These can reveal sensitive policy or identifiers, so summarize rather than attach raw output. PF and the macOS application firewall do not reveal every Network Extension content-filter or vendor per-app decision. Check the VPN vendor UI, configuration profile, or administrator policy for:

- included/excluded subnets and address families;
- full-tunnel versus split-tunnel behavior;
- per-app or per-process rules that include/exclude `sshd`;
- per-user restrictions for `<SSH_USER>`;
- local-LAN/public-egress exclusions;
- endpoint firewall or content-filter denials.

### 4.3 Source Mac A: isolate SOCKS, IP, DNS, and application behavior

Confirm that Relux's loopback listener exists:

```bash
/usr/bin/nc -vz -G 5 127.0.0.1 "$SOCKS_PORT"
```

Use an authorized plain-HTTP synthetic path for the following three tests:

```bash
/usr/bin/curl --silent --show-error --output /dev/null \
  --connect-timeout 5 --max-time 10 \
  --socks5 "127.0.0.1:$SOCKS_PORT" \
  "http://$TARGET_IP:$TARGET_PORT/<nonsecret-health-path>"
```

```bash
/usr/bin/curl --silent --show-error --output /dev/null \
  --connect-timeout 5 --max-time 10 \
  --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
  "http://$TARGET_HOST:$TARGET_PORT/<nonsecret-health-path>"
```

```bash
/usr/bin/curl --silent --show-error --output /dev/null \
  --connect-timeout 5 --max-time 10 \
  --socks5 "127.0.0.1:$SOCKS_PORT" \
  "http://$TARGET_HOST:$TARGET_PORT/<nonsecret-health-path>"
```

Record each exit code separately:

1. Numeric IP through SOCKS tests remote TCP routing without destination DNS.
2. Hostname through `--socks5-hostname` tests remote/proxy DNS.
3. Hostname through `--socks5` is a deliberate local-DNS comparison.

If the first two succeed but the real application fails:

- configure SOCKS5, not an HTTP proxy;
- enable “proxy DNS,” “remote DNS,” or the application's SOCKS5h equivalent;
- check whether the application bypasses proxies for the private domain;
- disable QUIC/HTTP/3 only as a reversible diagnostic and confirm TCP fallback;
- check for application-owned DoH, cached DNS, or a non-proxied helper process.

Do not treat automatic macOS network-service SOCKS settings as system routing. Some applications honor them and others do not; UDP and ICMP still do not traverse `ssh -D`.

To prove the system-routing boundary:

```bash
/sbin/route -n get "$TARGET_IP"
```

An ordinary source-Mac route is expected. Do not add a route to “fix” it; the local SOCKS listener, not an IP interface, is the supported data plane.

For a temporary manual OpenSSH reproduction, use the same account and a synthetic destination:

```bash
/usr/bin/ssh -vvv -N \
  -D "127.0.0.1:$SOCKS_PORT" \
  -E .temp/TASK-260728-2eggfg/ssh-redact-before-sharing.log \
  '<REMOTE_ALIAS>'
```

Use the existing trusted host-key configuration. Do not add host-key bypass flags. Before sharing a log, remove hostnames, usernames, addresses, key paths/fingerprints, and banners while retaining the forwarding error phrase and exit status. Relux's normal quiet log level will not expose this per-channel detail, so the manual command is diagnostic only.

### 4.4 Decision tree

```text
Remote Mac B: numeric TCP test succeeds?
├─ No
│  ├─ route points outside VPN / no included route
│  │    -> remote VPN route or split-tunnel policy problem
│  ├─ route points at VPN but timeout/denial
│  │    -> VPN policy, endpoint filter, destination firewall, or service problem
│  └─ only one address family fails
│       -> IPv4/IPv6 route or service-family mismatch
└─ Yes
   ├─ Remote hostname test fails
   │    -> remote resolver, search domain, or returned address-family problem
   └─ Source Mac A: numeric curl through SOCKS succeeds?
      ├─ No
      │  ├─ SSH says "administratively prohibited"
      │  │    -> AllowTcpForwarding/DisableForwarding/PermitOpen/key restriction
      │  ├─ SSH server connect gets no route/timeout/refused
      │  │    -> sshd worker has different VPN/process policy, firewall, or target state
      │  └─ SOCKS listener unavailable
      │       -> tunnel/session/local-port problem
      └─ Yes
         ├─ SOCKS5h hostname fails
         │  ├─ remote hostname also fails -> remote DNS
         │  └─ remote hostname succeeds -> PermitOpen name spelling or
         │       shell-versus-sshd process/DNS policy difference
         ├─ SOCKS5h succeeds; local-resolution SOCKS fails
         │    -> private name must use proxy-side DNS
         ├─ curl succeeds; application fails
         │    -> SOCKS-unaware app, bypass/DoH/cache, helper process, or UDP/QUIC
         └─ curl works but ping/system route does not
              -> expected ssh -D boundary; system routing was never installed
```

### 4.5 Failure signatures

| Symptom or error | Distinguishing check | Likely class | Next action |
|---|---|---|---|
| Remote numeric `nc` says no route or times out | `route -n get` does not select eligible VPN path | No remote route/split-tunnel exclusion | Correct remote VPN policy through its owner; do not change Relux |
| Remote numeric shell test works, SOCKS numeric test times out | Compare VPN/process policy for terminal versus authenticated `sshd` worker | Per-app/per-user VPN or endpoint-filter denial | Include the SSH server process/account if supported, or use a policy-compatible remote relay |
| SSH reports forwarding administratively prohibited | Effective `sshd -T` and key restrictions | SSH forwarding policy | Administrator explicitly permits needed forwarding/destinations |
| Numeric SOCKS works, SOCKS5h hostname fails | Remote `dscacheutil`/`scutil --dns` | Remote DNS/search-domain failure, family mismatch, or name-restricted `PermitOpen` | Fix resolver/policy or use exact permitted spelling |
| SOCKS5h works, curl `--socks5` hostname fails | Compare source and remote DNS answers | DNS-only/local-resolution failure | Enable proxy DNS/SOCKS5h |
| curl through SOCKS works, target application fails | Application proxy/DoH/QUIC settings | SOCKS-unaware client or bypass | Configure application explicitly or choose a packet-tunnel product |
| TCP works; QUIC, UDP service, or SOCKS UDP probe fails | Force a TCP-capable test | UDP-dependent protocol | TCP fallback or a separate UDP-capable transport/relay |
| Private prefix works; public egress does not change | Test organization-owned public endpoint and inspect remote included routes | Split tunnel/public-egress exclusion | Expected unless remote VPN has an eligible default route |
| SOCKS curl works; `ping` and source route still fail | Inspect source route table | System-routing expectation | Expected; `ssh -D` is not an IP tunnel |
| Immediate `Connection refused` | Test remote shell and exact IP/port | Service/listener/family mismatch, not necessarily VPN | Confirm service bind, port, and IPv4/IPv6 |

## 5. Candidate comparison

| Candidate | TCP | UDP / ICMP | DNS behavior | Local privilege | Remote requirements | Apple entitlement / distribution impact | Security and product fit |
|---|---|---|---|---|---|---|---|
| **Current Relux `ssh -D` + app SOCKS5/SOCKS5h** | Yes, for SOCKS-aware apps | No | Local with ordinary SOCKS5; remote with SOCKS5h/proxy DNS | None; loopback listener | SSH account; forwarding allowed; destination eligible for remote VPN/policy | None beyond current app | Smallest surface. Keep loopback-only. Best v0.2.0 fit when limitation is explicit |
| **macOS network-service SOCKS setting pointed at `ssh -D`** | Only for clients that honor the setting | No | Client-dependent; leakage/bypass remains possible | Configuration change may require authorization and affects a network service | Same as current `ssh -D` | No packet-tunnel entitlement, but broad host setting creates lifecycle/restore UX | Not true system routing; silent mutation and incomplete coverage make it a poor default |
| **sshuttle on macOS** | Transparent interception for routed TCP | Arbitrary UDP/ICMP: no; optional DNS interception: yes | `--dns` can capture selected DNS requests | Local `sudo`/root for PF | Normal SSH account plus compatible Python; no permanent remote install | CLI/admin workflow; uses PF, which Apple does not support as a product VPN API | Useful operator workaround on managed Macs; inappropriate embedded Relux data plane |
| **Standalone tun2socks** | Yes | Engine-dependent; **not through current OpenSSH `-D`**, which lacks UDP association | Must route/configure DNS deliberately | TUN and route administration | Existing SOCKS is sufficient only for TCP; UDP needs a compatible upstream/relay | Standalone privileged helper is a packaging/distribution burden | Can create system-like TCP routing but adds leak, route, lifecycle, and privilege risks |
| **`NEPacketTunnelProvider` + userspace stack/tun2socks** | Yes | Only with a UDP-capable transport/remote relay; `direct-tcpip` alone is TCP | `NEDNSSettings`, match domains, and included/excluded routes | User-approved VPN configuration; no ad-hoc root helper | Current SSH server can carry TCP channels; robust UDP requires separately authenticated relay/transport | Network Extension capability, provisioning, extension target, Apple intended-use/review gate | Correct Apple product architecture for system routing, but a separate milestone rather than a v0.2.0 patch |
| **OpenSSH `ssh -w` tun tunnel** | Yes as IP packets | Yes, subject to tunnel/routing/NAT | Resolver/routes must be configured separately | TUN device and routes generally require admin | `PermitTunnel`, device permission, IP forwarding/routes and often NAT/admin | Stock portability is poor; this macOS fixture had no `/dev/tun*`; unsuitable normal app distribution | Broad L3 trust and remote gateway changes; conflicts with rootless/no-remote-admin baseline |

### Candidate notes and source checks

**SOCKS-aware configuration.** This is the only option requiring no new data plane. It succeeds when the application uses SOCKS5, delegates private names through SOCKS5h, and uses TCP. It is not a fallback for apps that require a route or UDP.

**sshuttle.** The official [manual](https://sshuttle.readthedocs.io/en/latest/manpage.html) and [requirements](https://sshuttle.readthedocs.io/en/latest/requirements.html) describe TCP and DNS capture, macOS PF use, local root privileges, and a remote Python requirement. It does not provide general UDP forwarding. Apple states that PF is not a supported product API in [TN3165: Packet Filter is not API](https://developer.apple.com/documentation/technotes/tn3165-packet-filter-is-not-api), so this is an operator tool, not an App Store-oriented Relux implementation.

**tun2socks.** HEV's primary [project documentation](https://github.com/heiher/hev-socks5-tunnel) describes IPv4/IPv6 and TCP/UDP capabilities. Those UDP modes require a compatible upstream path; OpenSSH dynamic forwarding supplies only SOCKS `CONNECT`, so pairing the engine with today's Relux endpoint remains TCP-only. Standalone macOS use also requires a TUN interface, routes, DNS handling, cleanup, and elevated authority.

**Network Extension.** [`NEPacketTunnelProvider`](https://developer.apple.com/documentation/networkextension/nepackettunnelprovider) is Apple's supported packet-tunnel API. A product must configure routes, DNS, MTU, packet flow, failure cleanup, and an actual transport. It also needs the [`com.apple.developer.networking.networkextension`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension) entitlement and provisioning. Apple's [TN3120](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers) intended-use guidance remains a product gate. Split DNS uses [`NEDNSSettings.matchDomains`](https://developer.apple.com/documentation/networkextension/nednssettings/matchdomains).

**`ssh -w`.** OpenSSH documents `-w` as a tunnel-device request and requires server `PermitTunnel`; its VPN example also requires interface addresses and routes in [`ssh(1)`](https://man.openbsd.org/ssh#-w). The server default for [`PermitTunnel`](https://man.openbsd.org/sshd_config#PermitTunnel) is `no`, and device permissions still apply. OpenSSH's Darwin build selects its BSD TUN implementation in pinned [`configure.ac`](https://github.com/openssh/openssh-portable/blob/V_10_2_P1/configure.ac#L787-L815), which opens `/dev/tunN` or `/dev/tapN` in [`port-net.c`](https://github.com/openssh/openssh-portable/blob/V_10_2_P1/openbsd-compat/port-net.c#L200-L250). The controlled macOS 26.5 fixture exposed no such stock device node, so `ssh -w` is not a defensible portable baseline.

## 6. Controlled reproduction and fact-check evidence

### 6.1 Fixture

The synthetic fixture used only loopback:

- HTTP service: `127.0.0.1:40180`;
- test `sshd`: `127.0.0.1:40122`;
- dynamic SOCKS listener: `127.0.0.1:40181`;
- a throwaway key and isolated known-hosts/config under `.temp/TASK-260728-2eggfg/fixture`.

No production Swift, system route, system resolver, PF, production SSH configuration, VPN configuration, private network, or external destination was changed or contacted.

### 6.2 Observations

1. Numeric SOCKS destination `127.0.0.1` reached the synthetic service.
2. SOCKS5h destination `localhost` reached the service. Server debug showed resolution first trying `::1`, then `127.0.0.1`.
3. curl's ordinary `--socks5` resolved `localhost` locally to `::1`; the fixture's IPv4-only service refused it. This expected-red branch exited `97`.
4. `lsof` showed the accepted service connection paired with an established outbound socket owned by user `iv`'s `sshd-sess`, not by the source curl process.
5. A raw SOCKS5 `UDP ASSOCIATE` probe received no success response. Client debug recorded that only SOCKS5 connect is supported.
6. The effective synthetic server configuration reported `allowtcpforwarding local`, `disableforwarding no`, `permitopen any`, and `permittunnel no`.

These observations independently reproduce:

- destination TCP ownership on the remote SSH side;
- the local-versus-remote DNS distinction;
- an IPv6/IPv4 failure signature that can look like a VPN problem;
- OpenSSH's TCP-only dynamic-forward behavior.

### 6.3 Validation ledger

Each gate was run directly as a standalone process without `tee` or a status-masking pipeline.

| Command | Exit | Result |
|---|---:|---|
| `task-board m 'set_status(TASK-260728-2eggfg, status=analysis)'` | 0 | Required researcher start transition |
| `/usr/sbin/sshd -t -f .temp/TASK-260728-2eggfg/fixture/sshd_config` | 0 | Synthetic server configuration valid |
| First `.temp/TASK-260728-2eggfg/fixture/run_fixture.zsh` | 97 | **Expected-red and reported as failing:** local-resolution mode selected `::1` for an IPv4-only target |
| Revised `.temp/TASK-260728-2eggfg/fixture/run_fixture.zsh` | 0 | Harness explicitly asserted the expected-red branch, IP success, SOCKS5h success, and UDP rejection |
| `/usr/sbin/sshd -T -f <fixture-config> -C user=iv,host=localhost,addr=127.0.0.1` | 0 | Effective forwarding policy captured |
| `/usr/sbin/scutil --dns` | 0 | Read-only resolver diagnostic works on fixture Mac |
| `/usr/sbin/scutil --nwi` | 0 | Read-only network-information diagnostic works |
| `/sbin/route -n get 127.0.0.1` | 0 | Read-only route diagnostic works and selected loopback |
| `/usr/sbin/netstat -rn -f inet` | 0 | Read-only IPv4 route-table diagnostic works |
| `/usr/sbin/netstat -rn -f inet6` | 0 | Read-only IPv6 route-table diagnostic works |
| `/usr/bin/dscacheutil -q host -a name localhost` | 0 | Read-only resolver comparison returned both loopback families |
| `ls -l /dev/tun* /dev/utun*` | 1 | **Expected-red and reported as failing:** zsh found no matching stock device nodes on this fixture |
| `zsh -f -c '<NULL_GLOB array assertion for /dev/tun* and /dev/utun*>'` | 0 | A non-erroring assertion independently confirmed zero matching device nodes |
| `zsh -f -c '<required-section fixed-string assertions>'` | 0 | Research artifact contains every required model/runbook/matrix/recommendation/source section |
| `git diff --check -- <research-artifact> <logbook-artifact>` | 0 | Markdown artifacts contain no whitespace errors |

The fixture is proof of OpenSSH mechanics, not proof of any specific VPN vendor's routing policy. A real two-Mac case still requires the redacted runbook because per-app policy, included routes, firewall decisions, and private DNS are environment-dependent.

## 7. Recommendation and exact follow-up scope

### 7.1 v0.2.0 action

Keep the existing transport and make its boundary explicit:

1. Label every displayed endpoint as an **application SOCKS5 proxy**.
2. State **TCP only; not a system VPN** next to the connection instructions.
3. Tell users with private names to enable **proxy DNS / remote DNS / SOCKS5h**.
4. State that the remote VPN must route and permit sockets opened by the authenticated `sshd` forwarding process/account.
5. Provide the numeric-IP, SOCKS5h-hostname, and application-level checks from this runbook with redaction guidance.
6. Avoid automatic system proxy, PF, route, DNS, remote `sshd`, or VPN mutations.

This scope has been recorded as `TASK-260728-3rs1x2`, “add-socks-vpn-reachability-guidance,” under the same story. Its acceptance tests require copy/help coverage and verify that tunnel-launch semantics remain unchanged.

### 7.2 Separate future system-VPN scope

If product intent is that arbitrary source-Mac applications inherit private routes, this is not an `ssh -D` configuration tweak. It is the separately specified Network Extension product:

- pass the Apple intended-use/entitlement gate;
- use `NEPacketTunnelProvider` and a userspace IP stack/tun2socks layer;
- define included/excluded routes, IPv4/IPv6, split DNS, search/match domains, MTU, reconnect, and failure cleanup;
- retain authenticated `direct-tcpip` channels for TCP only if they satisfy performance and policy;
- add a separately authenticated and authorized remote relay/transport for UDP, or explicitly exclude UDP;
- prevent DNS and traffic leaks across connect/reconnect/failure transitions;
- test TCP/UDP/DNS, per-app versus full-tunnel behavior, route precedence, remote policy, sleep/wake, IPv4/IPv6, and extension lifecycle;
- preserve least privilege and destination authorization; do not expose the local SOCKS listener beyond loopback.

The repository already treats this as a distinct architecture rather than a legacy-tunnel feature. Folding it into v0.2.0 would bypass entitlement, distribution, UX, security, and remote-transport decisions.

## 8. Source-to-claim fact check

| Claim | Primary evidence |
|---|---|
| `ssh -D` is a local SOCKS listener whose connections are forwarded from the remote machine | OpenBSD/OpenSSH [`ssh(1) -D`](https://man.openbsd.org/ssh#-D) |
| `direct-tcpip` carries host/port and originator metadata; the recipient connects | IETF [RFC 4254, section 7.2](https://www.rfc-editor.org/rfc/rfc4254#section-7.2) |
| The remote server resolves and connects, after privilege drop to the authenticated UID | OpenSSH 10.2p1 [`channels.c`](https://github.com/openssh/openssh-portable/blob/V_10_2_P1/channels.c#L4729-L4784) and [`sshd-session.c`](https://github.com/openssh/openssh-portable/blob/V_10_2_P1/sshd-session.c#L443-L445) |
| OpenSSH dynamic forwarding accepts SOCKS `CONNECT`, not UDP association | OpenSSH 10.2p1 [`channels.c`](https://github.com/openssh/openssh-portable/blob/V_10_2_P1/channels.c#L1684-L1688); protocol command definitions in [RFC 1928](https://www.rfc-editor.org/rfc/rfc1928) |
| Local versus proxy-side hostname resolution differs in curl | curl [`--socks5`](https://curl.se/docs/manpage.html#--socks5), [`--socks5-hostname`](https://curl.se/docs/manpage.html#--socks5-hostname), and [`CURLOPT_PROXYTYPE`](https://curl.se/libcurl/c/CURLOPT_PROXYTYPE.html) |
| Server policy can disable/restrict forwarding and destinations | OpenBSD/OpenSSH [`AllowTcpForwarding`](https://man.openbsd.org/sshd_config#AllowTcpForwarding), [`DisableForwarding`](https://man.openbsd.org/sshd_config#DisableForwarding), and [`PermitOpen`](https://man.openbsd.org/sshd_config#PermitOpen) |
| Apple VPN routing can use included/excluded/default/enforced and per-app rules | Apple [Routing your VPN network traffic](https://developer.apple.com/documentation/networkextension/routing-your-vpn-network-traffic) |
| Packet tunnels require Network Extension architecture and entitlement | Apple [`NEPacketTunnelProvider`](https://developer.apple.com/documentation/networkextension/nepackettunnelprovider) and [Network Extension entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension) |
| PF is not Apple's supported product API | Apple [TN3165](https://developer.apple.com/documentation/technotes/tn3165-packet-filter-is-not-api) |
| sshuttle on macOS uses PF, handles TCP/optional DNS, needs local privilege and remote Python | sshuttle [manual](https://sshuttle.readthedocs.io/en/latest/manpage.html) and [requirements](https://sshuttle.readthedocs.io/en/latest/requirements.html) |
| `ssh -w` requires tunnel devices and `PermitTunnel`; macOS build uses BSD device paths | OpenSSH [`ssh(1) -w`](https://man.openbsd.org/ssh#-w), [`PermitTunnel`](https://man.openbsd.org/sshd_config#PermitTunnel), and pinned portable source [`port-net.c`](https://github.com/openssh/openssh-portable/blob/V_10_2_P1/openbsd-compat/port-net.c#L200-L250) |

## 9. Answer to the problem statement

For the source Mac to reach a private network or egress path through today's Relux tunnel:

- configure the individual application to use SOCKS5 at Relux's loopback address and port;
- enable proxy-side DNS/SOCKS5h for names known only to the remote VPN;
- use a TCP-capable protocol;
- ensure remote OpenSSH forwarding policy permits the requested destination;
- ensure the remote VPN and security policy include the authenticated server-side SSH forwarding process/account and target prefix;
- verify remote route/DNS first, then numeric SOCKS, then SOCKS5h, then the real application.

If the requirement is instead “all applications and protocols should receive the remote VPN's network behavior,” current Relux configuration cannot provide it. That requirement needs the separately scoped Network Extension packet-tunnel architecture and a UDP-capable remote transport where UDP is required.

## 10. Limitations

- No production Mac, production SSH server, private VPN destination, or vendor policy was modified or probed.
- The controlled reproduction used one Mac and loopback to isolate OpenSSH process, DNS, and protocol mechanics.
- Actual VPN inclusion, firewall behavior, MDM/per-app rules, and destination authorization must be checked by the environment owner using the redacted runbook.
- The absence of `/dev/tun*` was observed on the macOS 26.5 fixture; it is not a claim that no third-party macOS TUN implementation can exist.
- Product-current statements distinguish repository documentation from unrelated uncommitted working-tree changes and do not claim those changes are released behavior.
