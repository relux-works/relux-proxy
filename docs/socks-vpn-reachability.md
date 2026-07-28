# Reaching private destinations through a Relux SOCKS tunnel

Each Relux endpoint is an Application SOCKS5 proxy — TCP only; not a system VPN
or system-wide routing. The listener is local (`127.0.0.1:<port>`), so only an
application configured to use that SOCKS endpoint uses the tunnel. Relux Proxy
does not install routes, change system proxy or DNS settings, or modify remote
VPN or SSH configuration.

## Use proxy-side DNS for private names

The SOCKS client decides where a hostname is resolved:

| Mode | Example | Destination name resolution |
| --- | --- | --- |
| Numeric IP | `--socks5` with an IP | No destination DNS lookup; isolates TCP routing and policy. |
| SOCKS5 local DNS | `curl --socks5` with a hostname | The source Mac resolves the name first and passes an IP through SOCKS. This can bypass remote private split DNS. |
| SOCKS5h / proxy DNS | `curl --socks5-hostname` or `socks5h://` | The hostname reaches the SSH server and the remote SSH machine resolves it. Use this for names known only to the remote VPN. |

Look for a client setting named **proxy DNS**, **remote DNS**, or **SOCKS5h**.
An application that uses its own DoH resolver or ignores SOCKS settings may not
follow this behavior.

## Run privacy-safe checks

Use an authorized synthetic service or organization-owned health endpoint. Do
not put private keys, certificates, tokens, cookies, authorization headers,
raw route tables, or full resolver output into a ticket. Use stable redactions
such as `<PRIVATE_V4>`, `<PRIVATE_HOST>`, `<TCP_PORT>`, and `<RELUX_LOCAL_PORT>`.
Record only each command's exit code and the relevant error phrase.

Set placeholders independently on the source and remote Macs:

```bash
TARGET_IP='<PRIVATE_V4>'
TARGET_HOST='<PRIVATE_HOST>'
TARGET_PORT='<TCP_PORT>'
SOCKS_PORT='<RELUX_LOCAL_PORT>'
```

On the remote Mac, signed in as the SSH account, first prove the exact TCP
service can be reached directly:

```bash
/usr/bin/nc -vz -G 5 "$TARGET_IP" "$TARGET_PORT"
/usr/bin/nc -vz -G 5 "$TARGET_HOST" "$TARGET_PORT"
/sbin/route -n get "$TARGET_IP"
```

On the source Mac, check the local listener and then use an authorized
plain-HTTP health path for an IP-versus-hostname comparison. Plain HTTP avoids
an HTTPS certificate-name mismatch when testing a raw IP address.

```bash
/usr/bin/nc -vz -G 5 127.0.0.1 "$SOCKS_PORT"

/usr/bin/curl --silent --show-error --output /dev/null \
  --connect-timeout 5 --max-time 10 \
  --socks5 "127.0.0.1:$SOCKS_PORT" \
  "http://$TARGET_IP:$TARGET_PORT/<HEALTH_PATH>"

/usr/bin/curl --silent --show-error --output /dev/null \
  --connect-timeout 5 --max-time 10 \
  --socks5-hostname "127.0.0.1:$SOCKS_PORT" \
  "http://$TARGET_HOST:$TARGET_PORT/<HEALTH_PATH>"

/usr/bin/curl --silent --show-error --output /dev/null \
  --connect-timeout 5 --max-time 10 \
  --socks5 "127.0.0.1:$SOCKS_PORT" \
  "http://$TARGET_HOST:$TARGET_PORT/<HEALTH_PATH>"
```

Interpret the three source checks in order:

1. Numeric IP through SOCKS tests remote TCP routing without destination DNS.
2. `--socks5-hostname` tests remote/proxy DNS for the private hostname.
3. Hostname with `--socks5` is the deliberate source-Mac local-DNS comparison.

If the proxy-DNS hostname check succeeds but the local-DNS hostname check
fails, configure the real application for proxy DNS/SOCKS5h. If the SOCKS curl
checks work but the application fails, it is likely SOCKS-unaware, bypassing the
proxy, using DoH, using a helper process, or preferring QUIC without TCP
fallback.

## Confirm the remote policy boundary

The destination TCP socket is opened on the remote SSH machine by the
authenticated `sshd` forwarding process/account. A successful command in a
remote interactive shell therefore does not by itself prove that the `sshd`
forwarding process is eligible for the same VPN or endpoint-security policy.

For a working connection, all of the following must be true:

- the remote VPN route includes the destination prefix and address family;
- SSH forwarding policy permits the destination (`AllowTcpForwarding`,
  `DisableForwarding`, `PermitOpen`, and key/certificate restrictions can deny
  it);
- a per-app, per-process, or per-user VPN/endpoint policy permits the
  authenticated `sshd` forwarding process/account;
- the remote firewall and destination service allow the selected remote source
  address and TCP port.

A remote route that points outside the VPN, an `administratively prohibited`
SSH error, a timeout from only the SOCKS test, or a firewall denial each points
to a remote policy or service owner. Correct that policy there; do not add
source-Mac routes, PF rules, system proxy settings, or Network Extension code
to Relux Proxy.

## Protocol boundary

OpenSSH dynamic forwarding accepts TCP SOCKS `CONNECT` requests. It does not
carry UDP associations, ICMP/ping, multicast, broadcast, or arbitrary IP
packets. QUIC/HTTP/3 is UDP-based and needs a TCP fallback to work through this
tunnel. A successful `route -n get` on the source Mac is not expected to show a
remote private route: the supported data plane is the per-application SOCKS
connection, not a system tunnel.
