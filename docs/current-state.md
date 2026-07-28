# Current state and future VPN boundary

Last verified: 2026-07-28.

## What exists

The repository builds one SwiftPM macOS 14 executable, `ReluxProxy`, packaged by
shell scripts as a menu bar `.app` and DMG.

The app:

- stores an ordered collection of profiles as one schema-versioned JSON Data
  value under `legacySocksProfiles.v1`, with stable UUID identity and unique
  explicit local ports;
- migrates the legacy `sshHost`, `sshAccount`, and `localPort` values exactly
  once, leaves those keys untouched for rollback, and never resurrects deleted
  profiles after the migration marker is set;
- owns one independent runtime session per profile, allowing multiple SSH
  children and SOCKS tunnels to connect concurrently on different local ports;
- launches `/usr/bin/ssh -N -C -D 127.0.0.1:<port>` with fail-fast, keepalive,
  timeout, batch-mode, and quiet logging options;
- passes an empty account as the bare host target, allowing system OpenSSH to
  use a matching `User` setting (or its normal default); a non-empty account is
  sent with `-l account` while the destination remains the bare host or alias,
  which explicitly overrides only the SSH user;
- accepts an IP address, hostname, or `Host` alias and lets the system client
  apply matching `~/.ssh/config` behavior such as `HostName`, `Port`,
  `IdentityFile`, and `ProxyJump`;
- binds the SOCKS listener only to IPv4 loopback (`127.0.0.1`) and keeps a
  separate trailing 4,000-character in-memory diagnostic for every session;
- rejects duplicate saved ports and externally occupied loopback ports without
  stopping or modifying another session or process;
- reports connecting, connected, disconnecting, disconnected, and failed states
  per row, with aggregate menu-bar status;
- prevents profile edits and removal while that profile owns a starting,
  connected, or stopping child;
- stops every child it owns on normal quit and starts every saved profile
  disconnected on the next launch, with no automatic retry or reconnect;
- exposes every listed endpoint as an Application SOCKS5 proxy — TCP only; not
  a system VPN or system-wide routing. Users configure a SOCKS-aware client
  manually and enable proxy DNS/SOCKS5h when private names need the remote
  resolver;
- intentionally runs outside the App Sandbox so it can spawn system SSH.

Tests cover profile migration and persistence, command construction and account
precedence, duplicate and OS port conflicts, concurrent independent lifecycle,
stale callback protection, diagnostics, active mutation rejection, and
coordinated shutdown. CI runs `swift test` and builds an ad-hoc-signed universal
application bundle.

The v0.2.0 GitHub release automation runs only on the dedicated
`relux-proxy-release` self-hosted macOS x64 runner. It selects the full Xcode
installation, imports the Relux Works Developer ID certificate into a
disposable keychain, builds a universal app, signs the DMG, requires accepted
notarization, staples and validates it with Gatekeeper, publishes checksums, and
attests the GitHub Release assets. It refuses the wrong repository, tag,
checkout, runner, identity, missing secret, or unsigned fallback. Runner
configuration does not create the v0.2.0 tag or claim that publication has
occurred; no GitLab v0.2.0 release is currently claimed.

## What does not exist

The current app is not a system VPN and does not contain:

- iOS targets;
- `NETunnelProviderManager` or packet-tunnel extensions;
- a userspace TCP/IP stack or packetFlow bridge;
- an embedded SSH implementation;
- UDP or system DNS forwarding;
- the remote `relux-relay` executable/protocol;
- shared profile/Keychain state between host and extension;
- Network Extension entitlements or provisioning;
- TestFlight/App Store release automation.

## Implemented legacy migration

The [multi-profile usage guide](../README.md#use) describes the user-facing
workflow. The implementation above provides the one-time migration, profile
persistence, OpenSSH account precedence, port ownership, diagnostics, and
independent lifecycle. Runtime state and reconnect intent are never persisted.

The [remote VPN reachability guide](socks-vpn-reachability.md) documents the
same application-level boundary, proxy-side DNS, and redacted diagnostics. A
remote VPN route, the authenticated `sshd` forwarding process/account policy,
and the remote firewall must all permit the requested TCP destination; Relux
Proxy does not change local system proxy, DNS, or routes.

The planned VPN product in `.spec/` remains a new architecture, not an
incremental toggle inside the legacy SOCKS controller.

For future VPN work:

- the stable macOS release path must remain reproducible;
- any migration from legacy SOCKS profiles to VPN profiles still needs its own
  explicit product decision;
- the system-SSH implementation may remain as a macOS legacy mode, be replaced,
  or be retired only through a product decision;
- SwiftPM tests and release history must not be silently discarded;
- Network Extension code must not be backported into the current manual app
  without the architecture and entitlement gates in `.spec/validation.md`.
