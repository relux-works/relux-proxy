# Tunnelblick wb-vpn reachability through SSH dynamic SOCKS

**Task:** `TASK-260728-u4j0pc`
**Date:** 2026-07-28
**Role:** researcher
**Host scope:** current macOS VPN/SSH Mac
**Safety:** read-only host inspection plus loopback-only connection tests; no VPN, route, DNS, firewall, sharing, SSH server, or private endpoint changes

Private addresses, internal names, VPN gateways, credentials, certificates,
keys, and raw logs are intentionally omitted. Network findings use only
interface names, address classes, prefix lengths, counts, and fixed error
categories.

## Executive finding

The current Relux/OpenSSH SOCKS design is sufficient for a SOCKS-aware
TCP application to reach a destination covered by wb-vpn.

The active wb-vpn session is a normal route-based OpenVPN split tunnel:

```text
source application on the other machine
  -> SOCKS5 at Relux 127.0.0.1:<port>
  -> SSH direct-tcpip channel
  -> authenticated sshd worker on this VPN Mac
  -> ordinary macOS getaddrinfo()/connect()
  -> global route lookup selects utun11 for a wb-vpn prefix
  -> private destination
```

The `sshd` socket does not inherit a frozen copy of its parent's routes.
OpenSSH creates a fresh TCP socket and macOS performs a route lookup when
`connect()` is called. The live wb-vpn routes are system routes, are not marked
interface-scoped, and all four unique server-pushed destination prefixes select
`utun11` in forced-host route lookups. They are therefore available to the
authenticated `sshd` worker just as they are to another ordinary process.

Proxy-side DNS is required for a private hostname. wb-vpn currently supplies
two private DNS servers, both are installed in the macOS default resolver, and
routes to both select `utun11`. The VPN server does not push a domain/search
suffix, so a canonical internal FQDN is safer than a short name.

The evidence does **not** support adding source-side routes, IP forwarding,
PF, `sshuttle`, a TUN device, or Network Extension code as the first fix.
Configure the individual application for SOCKS5 and enable proxy DNS /
SOCKS5h. A packet tunnel is justified only if the requirement is system-wide
coverage, SOCKS-unaware applications, UDP/QUIC without TCP fallback, ICMP, or
arbitrary IP routing.

One authorized destination is still required to prove the last
endpoint-specific hop. The minimal private input is a numeric address inside
the intended wb-vpn prefix, an authorized TCP port, and optionally its
canonical private FQDN plus a nonsecret health path. No network scan is needed.

## 1. Concrete host snapshot

| Area | Privacy-safe observation | Consequence |
| --- | --- | --- |
| Host | macOS 26.5, arm64 | Current-host evidence only |
| Tunnelblick | 8.0.3 build 6303 in `/Applications` | Matches the current stable release listed by Tunnelblick |
| Profile location | One exact wb-vpn package in Tunnelblick `Shared` scope | The package is present and selected by the active process |
| Profile protection | Package directory is readable; its single `config.ovpn` is `root:wheel`, mode `0700`, and unreadable to the login user | Raw directives, embedded material, and secrets were not exposed |
| Runtime | One Tunnelblick GUI process and one root OpenVPN process; the OpenVPN command contains the wb-vpn profile token | wb-vpn is active |
| OpenVPN | Runtime path token identifies OpenVPN 2.6.21 with OpenSSL 3.0.21 | Source checks use the applicable OpenVPN 2.6 behavior |
| OpenVPN state | Current wb-vpn log has one `Initialization Sequence Completed`, one opened-utun marker, no authentication failure, no explicit route failure, and no explicit DNS/resolver failure | The VPN is established |
| Active device | The wb-vpn log mentions only `utun11`; it has IPv4, MTU 1400, and no IPv6 address | `utun11` is the current wb-vpn device; the number is dynamic across reconnects |
| Other utuns | Thirteen utun interfaces exist; another utun has unrelated default/scoped state | Never identify wb-vpn by guessing the highest utun number |
| SSH server | OpenSSH 10.2p1; launchd job is loaded on demand and was idle before the loopback probe | Normal macOS Remote Login behavior |
| IP forwarding | IPv4 and IPv6 forwarding sysctls are `0` | Not a blocker: SOCKS terminates and creates TCP connections instead of forwarding IP packets |
| Application Firewall | Disabled; block-all disabled; stealth mode off | Not blocking the observed SSH/SOCKS path |
| PF | Status/rules require administrator privilege and were not readable | Target-specific PF policy remains an unverified low-level blocker |

Tunnelblick protects shared configurations so a non-admin user cannot directly
read this one. The effective runtime is nevertheless observable without
opening the profile: the active process identifies wb-vpn, the log records
the server-pushed options, and the live kernel route/resolver tables show which
options took effect.

## 2. wb-vpn route and DNS map

### 2.1 Server-pushed options

The current `PUSH_REPLY`, parsed without printing values, contains:

- seven IPv4 `route` directives representing four unique destinations;
- one `route-gateway`;
- one `ifconfig`;
- two RFC1918 DNS server addresses;
- no IPv6 route;
- no IPv4 or IPv6 redirect-gateway;
- no pushed `DOMAIN` or `DOMAIN-SEARCH`.

The four unique route shapes are:

| Redacted group | Class | Prefix | Push count |
| --- | --- | ---: | ---: |
| A | RFC1918 | `/8` | 2 |
| B | RFC1918 | `/14` | 2 |
| C | RFC1918 | `/18` | 2 |
| D | non-RFC1918 | `/31` | 1 |

The duplicate A/B/C pushes produce six `File exists` messages, including three
in route context. This is noisy server configuration, not the cause of the
reported reachability problem: the final unique routes exist and select the
VPN interface.

### 2.2 Live route table

`utun11` has six IPv4 table entries: the four unique pushed prefixes plus the
tunnel-connected/host entries. It has no IPv6 route entry. There is no wb-vpn
default route, so this is intentionally split tunneling.

Each of the four unique pushed destinations was checked locally with:

```text
route -n get -host <redacted-destination>
```

All four lookups exited `0`, selected `utun11`, and returned
`UP,GATEWAY,DONE,STATIC,PRCLONING`. The table entries are shown as `UGSc`/`UH`
and do not contain `I`. The local macOS `netstat(1)` manual defines `I` as
`RTF_IFSCOPE`; its absence confirms that these are not routes available only to
an already interface-bound socket.

The practical rule is:

```text
destination inside one of the four live prefixes -> utun11
destination outside them                         -> another route
```

An exact destination remains necessary to determine which side of that rule
the user's service occupies.

### 2.3 Scoped DNS

The two pushed DNS addresses were matched privately against `scutil --dns`.
Both appear:

- together in default resolver 1; and
- together in an `en0`-scoped copy of that resolver.

The default resolver contains one search domain, but the OpenVPN push contains
no domain/search directive; the existing suffix must not be assumed to be the
private suffix. A separate unrelated resolver is scoped to `utun4`.

Forced-host route lookup for each pushed DNS address exited `0` and selected
`utun11`. Thus a normal system resolver request made by the authenticated
`sshd` worker can reach the wb-vpn DNS servers.

Implications:

- a numeric SOCKS destination needs no destination DNS;
- `socks5://` / curl `--socks5` resolves a hostname on the source machine and
  can miss private DNS;
- `socks5h://` / curl `--socks5-hostname` passes the hostname through SSH so
  this VPN Mac resolves it;
- use the canonical private FQDN unless the VPN owner confirms the short-name
  search suffix.

## 3. Why `sshd` uses the wb-vpn routes

OpenSSH 10.2p1 implements the path in three relevant steps:

1. `serverloop.c` accepts a `direct-tcpip` channel only when TCP forwarding and
   authentication policy permit it, then calls `channel_connect_to_port`.
2. `channels.c` calls `getaddrinfo` for a hostname, creates a `SOCK_STREAM`
   socket, and calls `connect`.
3. macOS selects an outbound route for that socket. There is no source-side
   packet forwarding, NAT requirement, or route-table copy from the SSH client.

Current local policy evidence:

- two readable `sshd` configuration documents;
- one `Include`, no `Match` block;
- no explicit `AllowTcpForwarding`, `DisableForwarding`, `PermitOpen`, or
  related restriction;
- the OpenSSH defaults are therefore `AllowTcpForwarding yes`,
  `DisableForwarding no`, and unrestricted `PermitOpen`;
- two current-user `authorized_keys` entries, neither using `restrict`,
  `no-port-forwarding`, or `permitopen`;
- loopback SSH authentication succeeded;
- a loopback `ssh -D` test reached a numeric destination and a
  proxy-resolved hostname, both with exit code `0`.

This proves that direct forwarding is functional for the inspected account.
The actual Relux SSH account/key should still be checked if it is different.

**Answer to the inheritance question:** yes, an allowed `direct-tcpip` socket
whose destination matches a wb-vpn prefix will use `utun11` in the current
state. Technically it performs a fresh system route lookup rather than
inheriting a route object.

## 4. Failure modes kept separate

| Observation | Failure class | Interpretation / next check |
| --- | --- | --- |
| Relux local port is closed | Local SOCKS/SSH session | Fix the Relux profile, SSH authentication, or port conflict |
| Numeric target fails directly on this VPN Mac | Route, VPN server policy, destination ACL/firewall, or service | Check only the exact target route and authorized TCP port |
| Numeric direct test works here, but numeric SOCKS test says `administratively prohibited` | SSH policy | Inspect the actual account/key, `Match`, `DisableForwarding`, and `PermitOpen` |
| Numeric direct test works here, numeric SOCKS test times out | Process/user filter, PF, endpoint security, or transient target state | Current Tunnelblick system routes are eligible; compare the actual `sshd` account and target-specific policy |
| Numeric SOCKS succeeds; SOCKS5h hostname fails | Proxy-side DNS, short-name suffix, returned family, or name-specific `PermitOpen` | Test the canonical FQDN on this VPN Mac and use proxy DNS |
| SOCKS5h succeeds; ordinary `--socks5` hostname fails | Source-side DNS | Expected private-DNS split; keep SOCKS5h/proxy DNS enabled |
| SOCKS curl succeeds; real application fails | Application bypass, `NO_PROXY`, DoH, helper process, or UDP/QUIC | Configure that application explicitly; force a TCP diagnostic |
| `ping` or the source machine's route table still fails | System-routing expectation | Expected: `ssh -D` is not an IP tunnel |
| Target falls outside the four wb-vpn prefixes | Split-tunnel coverage | VPN owner must authorize and add the route; do not add a source-machine route |
| Target route is `utun11` but the service refuses | Endpoint/service ACL | The destination sees the VPN Mac's selected source, not the original source machine |

The current OpenVPN/Tunnelblick state rules out a disconnected tunnel,
missing effective pushed routes, and missing effective pushed DNS. The local
SSH tests rule out a blanket forwarding denial for the inspected account.
They cannot rule out an exact destination ACL, an account-specific key option
for another login, target-specific PF/content-filter policy, or a service that
is absent on the requested port.

## 5. Recommended SOCKS-only configuration and test sequence

### 5.1 Configure the source application

For the existing Relux profile:

1. Connect the Relux profile that SSHes to this VPN Mac.
2. Configure the individual application with SOCKS host `127.0.0.1`, the
   profile's displayed port, and SOCKS v5.
3. Enable **Proxy DNS when using SOCKS v5**, **remote DNS**, or the
   application's SOCKS5h equivalent.
4. Remove/disable any proxy-bypass rule for the private domain.
5. Use TCP. Disable QUIC/HTTP/3 only as a reversible diagnostic if the
   application has a TCP fallback.
6. Prefer the canonical internal FQDN; do not depend on an unverified short
   search suffix.

Relux itself already launches the system client with:

```text
/usr/bin/ssh -N -C -D 127.0.0.1:<port>
```

plus `ExitOnForwardFailure`, keepalive, timeout, batch-mode, and error-only
logging options. No Relux transport change is needed for this case.

### 5.2 Privacy-safe checks on this VPN Mac

Run these only for one explicitly authorized destination. Inputs are hidden
from terminal echo; output contains only counts, interface names, and exit
codes.

```zsh
read -r -s "TARGET_IP?Authorized numeric destination (hidden): "
printf '\n'
read -r -s "TARGET_HOST?Canonical private hostname (hidden; optional): "
printf '\n'
read -r "TARGET_PORT?Authorized TCP port: "

route_text=$(/sbin/route -n get -host "$TARGET_IP" 2>/dev/null)
route_rc=$?
route_if=$(awk -F': *' '/^[[:space:]]*interface:/ {print $2; exit}' <<< "$route_text")
printf 'route_exit=%d route_interface=%s\n' "$route_rc" "${route_if:-unresolved}"

/usr/bin/nc -z -G 5 "$TARGET_IP" "$TARGET_PORT" >/dev/null 2>&1
printf 'vpn_mac_numeric_tcp_exit=%d\n' "$?"

if [[ -n "$TARGET_HOST" ]]; then
  dns_text=$(/usr/bin/dscacheutil -q host -a name "$TARGET_HOST" 2>/dev/null)
  dns_rc=$?
  dns_answers=$(awk '/^ip_address:/ {n++} END {print n+0}' <<< "$dns_text")
  printf 'vpn_mac_dns_command_exit=%d answer_count=%d\n' "$dns_rc" "$dns_answers"

  /usr/bin/nc -z -G 5 "$TARGET_HOST" "$TARGET_PORT" >/dev/null 2>&1
  printf 'vpn_mac_hostname_tcp_exit=%d\n' "$?"
fi

unset TARGET_IP TARGET_HOST TARGET_PORT route_text dns_text
```

Expected route result for an included wb-vpn destination:
`route_exit=0 route_interface=utun11` (or the new wb-vpn utun number after a
reconnect).

### 5.3 Privacy-safe checks on the source Mac

```zsh
read -r "SOCKS_PORT?Relux local SOCKS port: "
read -r -s "TARGET_IP?Authorized numeric destination (hidden): "
printf '\n'
read -r -s "TARGET_HOST?Canonical private hostname (hidden): "
printf '\n'
read -r "TARGET_PORT?Authorized TCP port: "

/usr/bin/nc -z -G 5 127.0.0.1 "$SOCKS_PORT" >/dev/null 2>&1
printf 'relux_listener_exit=%d\n' "$?"

/usr/bin/nc -z -G 5 -X 5 \
  -x "127.0.0.1:$SOCKS_PORT" \
  "$TARGET_IP" "$TARGET_PORT" >/dev/null 2>&1
printf 'numeric_through_socks_exit=%d\n' "$?"
```

For an authorized plain-HTTP health endpoint, compare proxy-side and local
DNS without printing the name or response:

```zsh
read -r "HEALTH_PATH?Nonsecret health path (for example /health): "

/usr/bin/curl --silent --output /dev/null \
  --connect-timeout 5 --max-time 10 --noproxy "" \
  --proxy "socks5h://127.0.0.1:$SOCKS_PORT" \
  "http://$TARGET_HOST:$TARGET_PORT$HEALTH_PATH" 2>/dev/null
printf 'proxy_dns_hostname_exit=%d\n' "$?"

/usr/bin/curl --silent --output /dev/null \
  --connect-timeout 5 --max-time 10 --noproxy "" \
  --proxy "socks5://127.0.0.1:$SOCKS_PORT" \
  "http://$TARGET_HOST:$TARGET_PORT$HEALTH_PATH" 2>/dev/null
printf 'local_dns_hostname_exit=%d\n' "$?"

unset SOCKS_PORT TARGET_IP TARGET_HOST TARGET_PORT HEALTH_PATH
```

Do not use `--insecure`. For HTTPS, use the canonical hostname and the
organization's trusted CA; use the numeric `nc` check to isolate TCP routing.

Interpret in this order:

1. direct numeric TCP on the VPN Mac;
2. numeric TCP through SOCKS;
3. hostname TCP on the VPN Mac;
4. hostname through `socks5h`;
5. the real application.

That order separates routing, SSH forwarding, proxy-side DNS, and application
behavior without scanning or dumping private data.

## 6. SOCKS versus TUN/system routing

### Recommendation

Use the existing SOCKS path for this wb-vpn case when the required application:

- supports SOCKS5;
- uses TCP;
- can enable SOCKS5h/proxy DNS; and
- targets one of the current wb-vpn prefixes.

This is the smallest and least-privileged fix. It preserves Relux's loopback
security boundary and requires no system or VPN changes.

### Escalate only for a different requirement

| Requirement | Appropriate direction |
| --- | --- |
| One or more SOCKS-aware TCP apps | Current Relux `ssh -D` plus SOCKS5h |
| Transparent TCP for apps that ignore SOCKS, managed operator workflow | `sshuttle` can be evaluated separately, but on macOS it uses PF/admin privileges and is not Relux's supported product data plane |
| System-wide routes, UDP, ICMP, robust DNS policy, arbitrary apps | The separately specified `NEPacketTunnelProvider`/userspace-stack product |
| Stock `ssh -w` TUN | Not a portable macOS baseline; requires tunnel devices, `PermitTunnel`, routes, forwarding, and usually admin changes on both ends |

Do not change this Mac's `net.inet.ip.forwarding`, enable Internet Sharing,
add NAT, or add source-machine routes for `ssh -D`. Those changes solve an IP
forwarding problem that this application proxy does not have.

## 7. Remaining endpoint-specific proof

No private destination was contacted. To close the last environment-specific
question, the owner must privately supply or confirm:

- one authorized numeric destination inside the intended wb-vpn network;
- one authorized TCP port and protocol;
- the canonical private FQDN, if hostname access matters;
- for HTTP, a nonsecret low-impact health path and expected status class.

That is sufficient to run the sequence above once. A subnet scan, raw packet
capture, full route table, full resolver dump, or profile disclosure is not
required.

## 8. Validation and evidence ledger

Commands designated as gates were run directly without `tee`. Expected-red
results remain reported as failures.

| Check | Exit | Result |
| --- | ---: | --- |
| Required task status transition | 0 | Task entered `analysis` |
| Tool readiness gate | 0 | All required host and board tools found |
| Direct shared-profile config parser | 1 | **Expected-red:** `config.ovpn` is root-only |
| Non-interactive privilege probe (`sudo -n true`) | 1 | **Expected-red:** administrator password required; no privilege escalation used |
| Current wb-vpn log/state parser | 0 | `utun11`, pushed routes/DNS, and initialized state identified without raw values |
| First exact network-form route gate without `-host` | 1 | **Expected-red:** macOS `route` parsed two network-base forms differently and selected `en0`; this was a CLI query-shape issue |
| Inside-prefix route gate | 0 | All four representative addresses selected `utun11` |
| Corrected forced-host route gate | 0 | All four exact pushed destinations selected `utun11` |
| Pushed-DNS route gate | 0 | Both DNS destinations selected `utun11` |
| `scutil --dns` parser | 0 | Both pushed DNS servers matched the current default resolver |
| Effective `sshd -T` as non-root | 1 | **Expected-red:** protected host keys unavailable |
| Readable sshd-config/key-option fallback | 0 | No global, Match, or current-key forwarding restriction found |
| Loopback SSH authentication | 0 | Current account authenticated through launchd sshd |
| Loopback curl through `ssh -D` | 0 | Numeric and proxy-resolved hostname both succeeded |
| Loopback `nc -X 5` through `ssh -D` | 0 | Numeric and hostname TCP probes both succeeded |
| Application Firewall state queries | 0 | Firewall, block-all, and stealth mode disabled |
| PF status query | 1 | **Expected-red:** status requires administrator privilege |
| Initial artifact IPv4 inventory | 2 | **Expected-red:** the first ripgrep expression used look-around without `--pcre2`; no artifact conclusion was drawn from it |
| Corrected artifact IPv4 inventory | 0 | PCRE2 scan found only the documented `127.0.0.1` loopback literal |
| IPv4 privacy gate | 0 | Every IPv4 literal in both artifacts is `127.0.0.1` |
| Secret-material gate | 0 | No PEM marker, inline OpenVPN key/cert block, credential-file argument, or long base64-like payload found |
| Required-section gate | 0 | All ten findings sections are present |
| Initial Markdown hygiene gate | 1 | **Expected-red:** five intentional two-space Markdown line breaks were flagged; they were removed |
| Corrected Markdown hygiene gate | 0 | Fourteen code-fence markers are balanced and no trailing whitespace remains |
| Local-reference gate | 0 | Every cited repository file exists |
| Scoped `git diff --check` | 0 | No whitespace error reported for the two research paths |

The failed unforced route gate was not relabeled as passing. Re-running the
lookup with the documented `-host` query form and with an address inside each
prefix independently produced exit `0` and selected `utun11`.

## 9. Source-to-claim fact check

| Claim | Primary or local evidence |
| --- | --- |
| Relux launches loopback OpenSSH dynamic forwarding | [`SSHCommandBuilder.swift`](../Sources/ReluxProxy/SSHCommandBuilder.swift), [`TunnelConfiguration.swift`](../Sources/ReluxProxy/TunnelConfiguration.swift), and [`docs/current-state.md`](../docs/current-state.md) |
| `ssh -D` is a local SOCKS listener and the connection is made from the remote machine | OpenBSD/OpenSSH [`ssh(1) -D`](https://man.openbsd.org/ssh#-D) |
| `direct-tcpip` policy is checked, then the server resolves and calls `connect()` | OpenSSH 10.2p1 [`serverloop.c`](https://github.com/openssh/openssh-portable/blob/V_10_2_P1/serverloop.c) and [`channels.c`](https://github.com/openssh/openssh-portable/blob/V_10_2_P1/channels.c) |
| TCP forwarding and destinations can be restricted | OpenBSD/OpenSSH [`AllowTcpForwarding`](https://man.openbsd.org/sshd_config#AllowTcpForwarding), [`DisableForwarding`](https://man.openbsd.org/sshd_config#DisableForwarding), and [`PermitOpen`](https://man.openbsd.org/sshd_config#PermitOpen) |
| `socks5://` resolves locally while `socks5h://` delegates hostname resolution | curl [`--socks5`](https://curl.se/docs/manpage.html#--socks5) and [`--socks5-hostname`](https://curl.se/docs/manpage.html#--socks5-hostname) |
| OpenVPN routes are added after connection; `route-noexec`/`route-nopull` would suppress them | OpenVPN [2.6 manual](https://openvpn.net/community-docs/community-articles/openvpn-2-6-manual.html) |
| On macOS, pushed `dhcp-option` values need a script/UI such as Tunnelblick | OpenVPN [2.6 `dhcp-option`](https://openvpn.net/community-docs/community-articles/openvpn-2-6-manual.html) and Tunnelblick [Set nameserver](https://tunnelblick.net/cConfigT.html) |
| Tunnelblick's DNS mode applies pushed DNS through scripts | Tunnelblick [Preferences](https://tunnelblick.net/cPreferences.html) |
| Tunnelblick needs privilege to configure devices, routes, and nameservers | Tunnelblick [FAQ](https://tunnelblick.net/cFAQ.html) |
| `connect()` initiates a stream-socket connection and reports route/network failures | Apple [`connect(2)`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/connect.2.html) |
| `I` means interface-scoped route and the interface column is the route used | Local macOS 26.5 `netstat(1)` manual |
| Current Relux is application SOCKS, not a system VPN | [`docs/socks-vpn-reachability.md`](../docs/socks-vpn-reachability.md) and [`README.md`](../README.md#remote-vpn-reachability) |

## 10. Limitations

- The protected static config was located but not read; effective runtime
  routes, DNS, process arguments, and OpenVPN state were inspected instead.
- PF rules and vendor endpoint-filter policy require authorized administrator
  inspection.
- The loopback reproduction proves current OpenSSH mechanics and policy for the
  inspected account, not a private endpoint's availability.
- `utun11` is the current interface name and can change after reconnect.
- No real private address, internal hostname, credential, certificate, key,
  raw profile, raw route table, raw resolver output, or raw log is contained in
  this artifact.
