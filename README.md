# Relux Proxy

Relux Proxy is a native macOS menu bar app for saved, independently controlled
SSH dynamic SOCKS5 tunnels. Multiple profiles can run concurrently when they
use different local ports. Every tunnel uses the system `/usr/bin/ssh`, so
hosts, keys, jump hosts, and other options from `~/.ssh/config` continue to
work; Relux Proxy does not parse or rewrite that file.

The repository also contains the approved specifications and implementation
backlog for a future macOS/iOS system VPN over SSH. That VPN is not implemented
yet. Start with [the specification index](.spec/README.md),
[the current-state inventory](docs/current-state.md), and
[the saved task-board workflow](docs/project-management.md).

## Use

1. Open Relux Proxy from Applications. On the first launch after upgrading, the
   previous `sshHost`, `sshAccount`, and `localPort` settings migrate into one
   saved profile. A clean install starts with `administrator@relux` on
   `127.0.0.1:1080`.
2. Use **Add profile** to save another SSH-reachable IP address, hostname, or
   `~/.ssh/config` alias and an explicit local SOCKS port. Ports must be unique
   across saved profiles.
3. Leave **Account** empty to let system OpenSSH use a matching config's `User`
   or its normal login-user default. A non-empty account is passed as an
   explicit `-l` override without changing the alias or SSH configuration.
4. Choose **Connect** on each profile you want to run. Profiles with different
   ports connect independently; a failure or occupied port affects only that
   row.
5. In Firefox, open **Settings → Network Settings**, select **Manual proxy
   configuration**, and enter the endpoint shown on the chosen profile:

   - SOCKS Host: `127.0.0.1`
   - Port: the profile's saved port
   - SOCKS v5
   - Proxy DNS when using SOCKS v5

6. Disconnect a profile before editing or removing it. Quitting Relux Proxy
   stops every SSH process launched by the current app run. Profiles remain
   saved, but tunnels do not reconnect automatically on the next launch.

### Installed-Mac two-tunnel check

After copying `ReluxProxy.app` to Applications, create two profiles with
different ports and connect both. Configure each SOCKS-aware client (or client
profile) with `127.0.0.1` and that profile's saved port. On the installed Mac,
use an organization-owned or otherwise authorized HTTPS endpoint that reports
the request's exit identity:

```bash
FIRST_SOCKS_PORT=1080
SECOND_SOCKS_PORT=1081
EXIT_IDENTITY_URL='https://<AUTHORIZED_EXIT_IDENTITY_ENDPOINT>'

/usr/bin/curl --fail --silent --show-error \
  --connect-timeout 10 --max-time 20 \
  --socks5-hostname "127.0.0.1:$FIRST_SOCKS_PORT" \
  "$EXIT_IDENTITY_URL"

/usr/bin/curl --fail --silent --show-error \
  --connect-timeout 10 --max-time 20 \
  --socks5-hostname "127.0.0.1:$SECOND_SOCKS_PORT" \
  "$EXIT_IDENTITY_URL"
```

Compare each result with the expected exit identity for its SSH host. The
values may legitimately match when both hosts share an egress, but each command
must succeed through its selected local port. Then disconnect one profile,
repeat the request through the other port, and confirm that the remaining
tunnel and its exit identity are unchanged. This physical external-SSH-host
step is intentionally not run by the automated test suite.

## Remote VPN reachability

Each listed endpoint is an Application SOCKS5 proxy — TCP only; not a system VPN
or system-wide routing. Configure an individual SOCKS-aware application to use
the endpoint. For private hostnames, enable the application's proxy DNS, remote
DNS, or SOCKS5h option so the remote SSH machine resolves the name instead of
the source Mac.

The remote VPN must route the destination and permit sockets opened by the
authenticated `sshd` forwarding process/account; SSH forwarding policy and the
remote firewall must also allow the connection. SOCKS-unaware applications,
UDP, ICMP, and QUIC-only traffic do not traverse this dynamic forward. Relux
Proxy does not alter macOS system proxy, DNS, or route settings.

Use the [redacted private-network reachability guide](docs/socks-vpn-reachability.md)
for numeric-IP, proxy-DNS hostname, and application-level checks.

## Download

The latest signed and notarized build always has the same asset name and URL
(GitHub authentication is required while this repository is private):

https://github.com/relux-works/relux-proxy/releases/latest/download/ReluxProxy.dmg

Versioned DMGs and SHA-256 checksums are available on the GitHub Releases page.
The v0.2.0 GitLab release is intentionally not advertised as published until
the Relux-owned GitLab hostname and project are confirmed and its protected
release pipeline passes. See the
[GitLab release runbook](docs/gitlab-release.md) for the exact gate and current
external blocker.

## Development

Requirements: macOS 14 or newer and Xcode 16 or newer.

```bash
make lint
make test
make app
make run
```

### Development tools

| Command | Purpose | Output or effect |
| --- | --- | --- |
| `make lint` | Run strict `swift-format` checks over app and test sources. | Diagnostics only; source files are not modified. |
| `make test` | Run the SwiftPM test suite. | SwiftPM build and test data in `.build/`. |
| `make app` | Build and sign the macOS application. | `dist/ReluxProxy.app`. |
| `make dmg` | Build the app, then package a disk image. | `dist/ReluxProxy-v<version>-universal.dmg`. |
| `make run` | Build the app, then open it. | Opens `dist/ReluxProxy.app`. |
| `shellcheck scripts/*.sh` | Lint packaging and release shell automation. | Diagnostics only; scripts are not modified. |
| GitLab `validate` pipeline | Run shell lint, Swift tests/build, and an ad-hoc universal app build on a macOS runner. | GitLab job logs and development build artifacts. |
| GitLab protected `v0.2.0` pipeline | Build, Developer ID sign, notarize, staple, Gatekeeper-check, publish, and re-download/verify the release assets. | GitLab Package Registry, Release assets, and maintainer-only audit artifacts. |

The app is intentionally not sandboxed because it needs to launch the system
SSH executable. Release bundles use the hardened runtime and are signed with
the Relux Works Developer ID. The implemented legacy SOCKS behavior is
documented in the [current-state inventory](docs/current-state.md); the
[specification index](.spec/README.md) remains limited to the separate planned
VPN.

Contributors must follow [CONTRIBUTING.md](CONTRIBUTING.md). Planned VPN work is
tracked in `.task-board/`; no VPN implementation should begin without explicit
approval of the generated plan.

## Release

Relux Proxy v0.2.0 uses the fail-closed GitLab pipeline documented in
[docs/gitlab-release.md](docs/gitlab-release.md). Do not add or push a GitLab
remote until the Relux-owned hostname, namespace/project, project ID, release
account, accepted commit SHA, protected macOS runner, and protected credentials
are explicitly confirmed. `gitlab.wildberries.ru` is unrelated and prohibited
for this release.

The existing GitHub tag workflow remains historical release automation. Both
paths require a real Developer ID signature; production mode in
`scripts/build-app.sh` refuses an ad-hoc fallback.
