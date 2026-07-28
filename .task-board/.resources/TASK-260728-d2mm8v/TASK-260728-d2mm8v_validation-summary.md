# TASK-260728-d2mm8v validation summary

## Green gates

| Command | Exit code | Result |
| --- | ---: | --- |
| `shellcheck scripts/*.sh` | 0 | Shell lint passed. |
| `bash -n scripts/*.sh` | 0 | Shell syntax passed. |
| `swift format lint --recursive --strict Sources Tests` | 0 | Swift formatting passed. |
| `swift test` | 0 | 49 tests in 8 suites passed. |
| `swift build` | 0 | Swift package build passed. |
| `SIGN_IDENTITY=- REQUIRE_DEVELOPER_ID=0 VERSION=v0.2.0 scripts/build-app.sh` | 0 | Universal ad-hoc development app built and verified. |
| `SIGN_IDENTITY='Developer ID Application: Relux Works, LLC (262RZ595FP)' REQUIRE_DEVELOPER_ID=1 VERSION=v0.2.0 scripts/build-app.sh` | 0 | Universal hardened-runtime Developer ID app built and verified. |
| `lipo dist/ReluxProxy.app/Contents/MacOS/ReluxProxy -verify_arch arm64 x86_64` | 0 | Intel and Apple silicon architectures verified. |
| `codesign --verify --deep --strict --verbose=2 dist/ReluxProxy.app` | 0 | App signature verified. |
| `VERSION=v0.2.0 scripts/create-dmg.sh` | 0 | Local universal DMG created. |
| DMG `codesign` and `codesign --verify` | 0 | Local DMG Developer ID signature verified. |
| `shasum -a 256 -c SHA256SUMS` | 0 | Local versioned/stable DMG hashes verified. |
| local Ruby parse of `.gitlab-ci.yml` | 0 | YAML parsed. |
| `git diff --check` | 0 | Tracked diff whitespace gate passed. |
| task-file trailing-whitespace gate | 0 | New/untracked task artifacts contain no trailing whitespace. |

## Expected-red production gate

`spctl -a -t open --context context:primary-signature -v
dist/ReluxProxy-v0.2.0-universal.dmg` returned exit code 3:

```text
rejected
source=Unnotarized Developer ID
```

This is an honest expected failure. App Store Connect notarization credentials
were not supplied, so no `notarytool submit`, stapling, production Gatekeeper
approval, package upload, GitLab tag, or GitLab Release operation was run.

The local pre-notarization checksum is:

```text
e5f1b16a82d3e5139d20e472ae4ce49bb5e2ad4d1897b060f68591d7a9a665b1  ReluxProxy-v0.2.0-universal.dmg
e5f1b16a82d3e5139d20e472ae4ce49bb5e2ad4d1897b060f68591d7a9a665b1  ReluxProxy.dmg
```

It is not a published checksum and will change when the production DMG is
notarized and stapled.

## Corrected validation failures

- Initial `lipo -verify_arch arm64 x86_64 <binary>`: exit 1 because the input
  order was wrong. Corrected invocation reran with exit 0.
- Initial required-Developer-ID build: exit 1 because an empty Bash array was
  incompatible with macOS Bash 3.2 under `set -u`. Explicit branches replaced
  the array; the rerun exited 0.
