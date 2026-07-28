# Legacy SOCKS multi-tunnel contract

**Contract version:** 1.1
**Status:** shipped product behavior in Relux Proxy v0.2.0; production GitLab
publication remains gated on the external release prerequisites
**Applies to:** the system-OpenSSH SOCKS product only; it does not define the
future system VPN.

This is the source of truth for the v0.2.0 extension of the macOS menu-bar SOCKS
app from one tunnel to independently controlled, concurrent tunnels. The
behavior described here is implemented and accepted in the v0.2.0 source
candidate; it is no longer planned-only work. Production distribution is a
separate evidence gate: as of 2026-07-28, no GitLab release is claimed because
the Relux-owned GitLab project and authorization have not been supplied. The
future VPN remains governed by the other documents in this directory.

The key words **MUST**, **SHOULD**, and **MAY** are normative.

## 1. Product boundary

A user MUST be able to save two or more SSH SOCKS profiles, choose each local
SOCKS port explicitly, and run profiles concurrently when their ports differ.
Each profile is independently started, stopped, diagnosed, edited, and removed.

Every tunnel MUST use the macOS system executable /usr/bin/ssh. Relux Proxy
does not parse, rewrite, import, or reimplement OpenSSH configuration semantics.
The app remains a manual, local-only SOCKS endpoint: users configure a
SOCKS-aware client themselves.

The current one-tunnel implementation and its sshHost, sshAccount, and
localPort preferences are migration inputs, not a second live configuration
model after migration.

## 2. Persisted profile model

### 2.1 Versioned store

The app MUST store the profile collection as one JSON Data value in the standard
app UserDefaults suite under the key legacySocksProfiles.v1. The payload has
this exact v1 shape:

    {
      "schemaVersion": 1,
      "profiles": [
        {
          "id": "4CA3B171-4C88-4B84-A33C-340B9F28DFF8",
          "host": "work-bastion",
          "account": "",
          "localPort": 1080
        }
      ]
    }

profiles preserves its array order. Every profile field is required:

| Field | Requirement |
| --- | --- |
| id | A unique, stable UUID string. It is the runtime and UI identity; host or port changes do not create a second identity. |
| host | The trimmed SSH destination token. It is non-empty, contains no whitespace, and does not begin with -. Its spelling and case are otherwise preserved. |
| account | The trimmed optional SSH account. An empty string is valid. A non-empty value contains neither whitespace nor @. |
| localPort | An integer in 1...65535, unique across the entire persisted profile list. |

The list is validated as a whole before a write. A failed add or edit MUST leave
the previous store intact; a duplicate port is rejected even when neither profile
is running. The product MUST NOT choose an ephemeral port, silently substitute
another port, or derive a port from the host.

Runtime state is deliberately absent from this payload. The app MUST NOT persist
connection state, process IDs, port reservations, diagnostics, or a reconnect
intent.

If the payload has an unknown newer schemaVersion, invalid required fields, or
invalid JSON, the app MUST preserve it without overwriting it, report a profile
persistence error, and refuse to start affected profiles. It MUST NOT fall back
to the legacy keys or silently create replacement profiles. A separately
confirmed reset MAY replace the invalid payload with an empty v1 store.

### 2.2 One-time migration from the single-tunnel preferences

The completion marker is the Boolean legacySocksProfiles.migration.v1.complete.
Migration is idempotent and follows this order on startup:

1. If a valid v1 payload already exists, load it. If the marker is absent, set
   the marker; do not create another profile.
2. If no v1 payload exists and the marker is absent, read legacy sshHost,
   sshAccount, and localPort. A missing value uses the current single-tunnel
   default for that field: relux, administrator, or 1080.
3. Trim and validate the resulting tuple with the v1 rules. When valid, write a
   v1 payload containing exactly one newly generated profile. When invalid or
   stored with an incompatible type, write an empty v1 payload and surface a
   bounded migration diagnostic rather than creating a partial profile.
4. Persist the v1 payload before setting the completion marker. A restart after
   a crash between those writes follows step 1, so it cannot duplicate a
   profile.
5. Once the marker is true, legacy keys are never read for migration again.
   This prevents deleted profiles from being resurrected on a later launch.

If the marker is already true but the v1 payload is absent, initialize an empty
v1 payload; do not revisit legacy keys.

Migration MUST leave sshHost, sshAccount, and localPort untouched for rollback
compatibility with the old application. The new implementation never writes
those legacy keys. An intentionally empty v1 profile list is valid and is not
repopulated from legacy preferences.

## 3. SSH destination and OpenSSH semantics

### 3.1 Destination input

host is one opaque destination argument for /usr/bin/ssh; it is not resolved or
classified by Relux Proxy. The same field therefore accepts all of the following
when OpenSSH accepts them:

| User input | Required handling |
| --- | --- |
| 203.0.113.10 or an IPv6 literal | Pass it as the destination token; do not turn it into an alias or perform app-side DNS resolution. |
| bastion.example.net | Pass it as the destination token; system OpenSSH resolves it and applies matching configuration. |
| work-bastion where Host work-bastion exists in ~/.ssh/config | Pass the alias unchanged. The system client evaluates that Host stanza and applicable Include or wildcard rules. |

The runner MUST use process argument APIs, never a shell command string. It
MUST NOT split a destination, synthesize an SSH configuration file, or inspect
~/.ssh/config to choose a key, port, jump host, or resolved hostname.

### 3.2 Account precedence

The normalized account field has exactly two modes:

| Account value | Required invocation behavior | Resulting User precedence |
| --- | --- | --- |
| Empty | Omit -l and pass the bare host destination. Do not construct @host. | User from a matching OpenSSH configuration stanza applies; if none applies, OpenSSH uses its normal system/default login-user behavior. |
| Non-empty | Pass -l account as a separate command-line option and pass the bare host destination. | The command-line account explicitly overrides configured User; no app-side configuration is changed. |

For example, with Host work-bastion, User deploy, HostName 10.0.0.8, and Port
2202 in ~/.ssh/config, an empty account connects as OpenSSH's configured deploy
user. An account of ops connects as ops; the alias still supplies its hostname
and port.

### 3.3 What the system client owns

Each launch retains the current SOCKS command behavior:

    /usr/bin/ssh -N -C -D 127.0.0.1:<localPort>
      -o ExitOnForwardFailure=yes
      -o ServerAliveInterval=30
      -o ServerAliveCountMax=3
      -o ConnectTimeout=15
      -o BatchMode=yes
      -o LogLevel=ERROR
      [-l <account>]
      <host>

Apart from those fixed operational options and the optional account override,
the installed OpenSSH client retains normal precedence and configuration
behavior. In particular, a matching alias MAY provide HostName, Port,
IdentityFile, ProxyJump, and related standard options. Relux Proxy MUST NOT add
command-line overrides for those settings.

Relux Proxy MUST NOT pass StrictHostKeyChecking, UserKnownHostsFile,
GlobalKnownHostsFile, or another host-key-policy override. Existing known_hosts
files, system defaults, and the user's OpenSSH configuration remain
authoritative. BatchMode=yes preserves the current non-interactive product
behavior; the app does not provide a host-key prompt, approve a key, or weaken
host-key verification.

## 4. Local port ownership

Every dynamic forward MUST bind exactly 127.0.0.1:<localPort>. IPv6 loopback,
localhost, all interfaces, LAN interfaces, 0.0.0.0, and every non-loopback
address are prohibited. The app MUST NOT enable a public proxy through
GatewayPorts or an equivalent option.

The profile registry owns the requested port while that profile is starting,
connected, or stopping. A start MUST reserve the profile and port in the
in-process registry before spawning SSH, so duplicate start requests cannot
create two children for the same profile. The implementation MAY probe whether
127.0.0.1:<localPort> is available before launch, but that probe is advisory:
the SSH process with ExitOnForwardFailure=yes is authoritative because a race
with another local process remains possible.

If a port is occupied by another profile, another application, or a surviving
child from an unclean prior exit, only the requested profile enters failed. The
app MUST NOT stop, reconfigure, replace, or kill a process it did not spawn in
the current run. Its diagnostic identifies the local endpoint and asks the user
to stop the owner or choose a different port. No other tunnel is affected.

## 5. Concurrent lifecycle contract

### 5.1 Independent runtime instances

The runtime registry is keyed by profile UUID. Each entry owns one immutable
configuration snapshot, one SSH child, one diagnostic buffer, and one lifecycle
generation token. Completion, readiness, stderr, and termination callbacks MUST
check that token before changing state; a late callback from an old child cannot
mark a restarted or removed profile as connected or failed.

Each profile has these visible states:

    disconnected -> connecting -> connected -> disconnecting -> disconnected
                        |             |
                        +-----------> failed -> connecting

An explicit stop during connecting is cancellation and follows the
disconnecting -> disconnected path. An unexpected child exit, forward failure,
readiness timeout, invalid configuration, or unavailable port moves only that
profile to failed. A profile remains failed until the user explicitly starts it
again; there is no automatic retry or reconnect.

connected requires both that the current-generation SSH child is still running
and that the expected 127.0.0.1:<localPort> endpoint accepts a connection. If
the child exits, its termination result wins over a racing readiness success.
The readiness timeout is 20 seconds, preserving the current 100 probes at
200 ms contract.

Starting, stopping, or failing one profile MUST NOT change another profile's
state, child process, diagnostic buffer, or configuration. Two or more profiles
with unique ports may therefore be connected at the same time.

### 5.2 Editing and removal

An active profile (connecting, connected, or disconnecting) is immutable. The
UI and model MUST reject host, account, and port edits while it is active; they
MUST NOT silently retarget, restart, or mutate a running child.

Removal is also rejected while a profile is active. The user must explicitly
stop it and wait until it is disconnected or a fully cleaned-up failed state
before removal. This prevents an orphaned SSH child from losing its owning
profile and accidental port reuse while an old process is exiting.

For an inactive profile, an edit validates the complete collection (including
port uniqueness) and persists atomically. A subsequent start uses the saved
snapshot. Removing an inactive profile removes only its persistent record and
runtime entry; it does not alter any other profile.

### 5.3 Stop, quit, and restart

An explicit stop sends a termination request to that profile's current child
and enters disconnecting. After two seconds, the app MAY escalate to a forced
termination only for that same child handle if it is still running. It MUST
observe termination before releasing the runtime reservation and report
disconnected for a user-requested stop.

On normal app quit, the app applies the same stop procedure to every child it
owns. It MUST never discover and kill processes merely by port, host, or command
line. A child that survived an unclean app crash is not considered owned after a
restart; a later port conflict is handled as the isolated failure in section 4.

After every launch, all persisted profiles begin disconnected, with no
persisted diagnostic or connection intent. The app MUST NOT automatically
reconnect, restore active tunnels, or modify another process to recreate the
pre-quit state.

## 6. Diagnostics and failure isolation

Diagnostics are per profile and runtime-only. Starting a profile clears its
prior diagnostic. Stderr from that profile's SSH child and generated launch or
readiness errors append only to its buffer. After each append, the product MUST
retain only the trailing 4,000 user-visible characters, matching the current
single-tunnel bound.

On an unexpected exit, the failure summary is the last non-empty diagnostic line
when available, otherwise the SSH exit status. A user-requested stop clears the
diagnostic after termination. Diagnostics MUST NOT be shared across profiles,
written as a persistent profile field, uploaded, or used as telemetry.

## 7. Explicit non-goals

This contract does **not** authorize:

- automatic reconnect, retry backoff, or restoration of tunnels after launch;
- mutation of macOS system proxy, PAC, browser, DNS, or routing settings;
- VPN behavior, NETunnelProviderManager, a Network Extension, packet-tunnel
  entitlements, or system-wide traffic capture/routing;
- editing, generating, importing, or rewriting ~/.ssh/config, known_hosts, SSH
  keys, passphrases, or identities;
- an embedded SSH client or replacement for /usr/bin/ssh;
- public, LAN, IPv6 local-listener, or non-loopback SOCKS exposure;
- automatic local-port allocation or a shared port for multiple profiles.

Future VPN work has separate product, architecture, security, entitlement, and
release gates. It does not implicitly inherit this legacy SOCKS persistence or
OpenSSH-alias contract.

## 8. Required implementation evidence

An implementation of this contract MUST demonstrate, with automated tests or
deterministic fakes where a live SSH server is unnecessary:

1. migration of valid legacy values into one v1 profile, idempotence across a
   restart, invalid-input handling, and non-resurrection after deleting all
   profiles;
2. exact account behavior for an IP, DNS hostname, and Host alias: empty account
   omits -l, while a non-empty account passes -l and overrides only User;
3. rejection of duplicate, invalid, and externally occupied local ports without
   interrupting an already connected profile;
4. independent concurrent start, failure, stop, and diagnostic buffers for at
   least two unique ports, including stale-callback protection;
5. rejection of active-profile edits and removal, orderly normal-quit child
   termination, and a restart with every profile disconnected and no auto-retry.

## 9. Version history

| Version | Date | Change |
| --- | --- | --- |
| 1.1 | 2026-07-28 | Recorded the implemented v0.2.0 multi-profile behavior as shipped product scope while keeping GitLab publication explicitly gated. |
| 1.0 | 2026-07-28 | Initial contract for the planned multi-profile legacy SOCKS extension. |
