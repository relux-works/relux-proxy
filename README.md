# Relux Proxy

Relux Proxy currently ships as a native macOS menu bar app that manages an SSH
dynamic SOCKS5 tunnel. It uses the system `/usr/bin/ssh`, so hosts, keys, jump
hosts, and other options from `~/.ssh/config` continue to work.

The repository also contains the approved specifications and implementation
backlog for a future macOS/iOS system VPN over SSH. That VPN is not implemented
yet. Start with [the specification index](.spec/README.md),
[the current-state inventory](docs/current-state.md), and
[the saved task-board workflow](docs/project-management.md).

## Use

1. Open Relux Proxy from Applications.
2. Enter the SSH host (or config alias), account, and local SOCKS port.
3. Choose **Connect**.
4. In Firefox, open **Settings → Network Settings**, select **Manual proxy configuration**, and set:
   - SOCKS Host: `127.0.0.1`
   - Port: the port shown by Relux Proxy (`1080` by default)
   - SOCKS v5
   - Proxy DNS when using SOCKS v5

The initial defaults are `administrator@relux` and `127.0.0.1:1080`.

## Download

The latest signed and notarized build always has the same asset name and URL
(GitHub authentication is required while this repository is private):

https://github.com/relux-works/relux-proxy/releases/latest/download/ReluxProxy.dmg

Versioned DMGs and SHA-256 checksums are available on the GitHub Releases page.

## Development

Requirements: macOS 14 or newer and Xcode 15.3 or newer.

```bash
make test
make app
make run
```

The app is intentionally not sandboxed because it needs to launch the system SSH executable. Release bundles use the hardened runtime and are signed with the Relux Works Developer ID.

Contributors must follow [CONTRIBUTING.md](CONTRIBUTING.md). Planned VPN work is
tracked in `.task-board/`; no VPN implementation should begin without explicit
approval of the generated plan.

## Release

Push a semantic version tag to build, sign, notarize, staple, attest, and publish both versioned and stable-name DMGs:

```bash
git tag -s v0.1.0 -m "Relux Proxy v0.1.0"
git push origin v0.1.0
```

The release workflow expects `MACOS_CERT_P12`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_P8` repository secrets. `ASC_KEY_P8` and `MACOS_CERT_P12` are base64 encoded.
