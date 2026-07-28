# GitLab macOS release runbook

This runbook is the production path for Relux Proxy v0.2.0. It deliberately
fails closed until the Relux-owned GitLab project, accepted commit, protected
runner, and Apple credentials are all present.

## Current external blocker

As of 2026-07-28, the production release target is not confirmed:

| Required identity | Current evidence |
| --- | --- |
| GitLab hostname | Not supplied. `gitlab.com` has no usable local API or SSH authorization. |
| Namespace/project | Not supplied. The only repository remote is `git@github.com:relux-works/relux-proxy.git`. |
| GitLab project ID | Not supplied. |
| Authorized release account | Not supplied. |
| Protected macOS release runner | Not discoverable without the target project. |
| Notarization credentials in GitLab | Not discoverable without the target project. |

`gitlab.wildberries.ru` is explicitly unrelated and prohibited for every
Relux source push, tag, package, and Release operation. A credential happens to
exist for that host on one development machine; its presence is not
authorization to use it.

Do not add a GitLab remote, push source, create a tag, or run a release until a
Relux owner replaces the unknown fields above with the exact hostname,
namespace/project, project ID, and authorized account in reviewed project
documentation.

## One-time project and runner setup

1. Confirm that the hostname and full namespace/project are owned by Relux.
   Confirm the project ID through the same project page or API and record the
   authorized operator.
2. Enable the project Package Registry and CI/CD.
3. Register a project-locked macOS runner using GitLab's supported user-mode
   `LaunchAgent` and shell executor. Give it both `macos` and `relux-release`
   tags, disable untagged jobs, mark it protected, and do not share it with
   untrusted projects. The runner needs Xcode, Swift, `glab`, `shellcheck`,
   Python 3, OpenSSL, and the standard macOS signing tools.
4. Protect the `v0.2.0` tag so only the release owner can create it.
5. Protect the `production` environment and require the project's chosen
   release approval.
6. Store the following project CI/CD variables. Secret values must be
   **Masked and hidden**, **Protected**, and have variable expansion disabled:

   | Variable | Handling |
   | --- | --- |
   | `MACOS_CERT_P12_B64` | Base64-encoded Relux Works Developer ID Application certificate plus private key. Secret. |
   | `MACOS_CERT_PASSWORD` | Non-empty password for the PKCS#12 payload. Secret. |
   | `MACOS_KEYCHAIN_PASSWORD` | Temporary CI keychain password. Secret. |
   | `ASC_KEY_ID` | App Store Connect API key ID. Secret metadata. |
   | `ASC_ISSUER_ID` | App Store Connect issuer ID. Secret metadata. |
   | `ASC_KEY_P8_B64` | Base64-encoded App Store Connect API private key. Secret. |

   Add these non-secret values as Protected variables:

   | Variable | Required value |
   | --- | --- |
   | `RELUX_GITLAB_HOST` | Exact confirmed hostname, without a scheme. |
   | `RELUX_GITLAB_PROJECT_PATH` | Exact case-sensitive namespace/project path. |
   | `RELUX_GITLAB_PROJECT_ID` | Exact positive numeric project ID shown by the confirmed project. |
   | `RELUX_ACCEPTED_RELEASE_SHA` | Full lowercase 40-character SHA accepted by review for v0.2.0. |

   The pipeline and preflight both require `RELUX_GITLAB_PROJECT_ID` to equal
   GitLab's `CI_PROJECT_ID` exactly. A missing, malformed, or mismatched value
   stops the job before any package, Release, or download URL is constructed.

GitLab documents that protected variables are limited to protected refs and
that sensitive values should be masked and hidden. Masking is only a log
defense, so the release runner and every pipeline change still require review:
<https://docs.gitlab.com/ci/variables/>.

GitLab's supported macOS runner setup uses a user-mode `LaunchAgent`; code
signing requires that user session and keychain access:
<https://docs.gitlab.com/runner/install/osx/>.

## Audited pipeline

`.gitlab-ci.yml` has three gates:

1. `validate` runs shell lint, Swift tests, a Swift build, and an ad-hoc-signed
   universal development bundle without production credentials.
2. `release_v0_2_0` runs only for the protected `v0.2.0` tag on the trusted
   `macos` + `relux-release` runner. It compares GitLab's actual host, project
   path, checked-out commit, and runner tags with the protected expected
   values. It imports the certificate into a disposable keychain; builds both
   `arm64` and `x86_64`; signs with the exact Relux Works Developer ID; submits
   the DMG with `notarytool`; requires `Accepted`; saves the notarization log;
   staples and validates the ticket; runs Gatekeeper; and produces checksums.
3. `verify_v0_2_0` first requires the Release metadata to name exactly the
   expected same-project Generic Package Registry links, then downloads all
   three assets through the job-token-supported Releases API endpoint
   `CI_API_V4_URL/projects/$CI_PROJECT_ID/releases/$CI_COMMIT_TAG/downloads/<asset>`.
   Browser-style `/-/releases/` permanent links remain end-user URLs and are
   not used as authenticated CI API targets. Redirects are followed manually
   with a fixed hop limit: `JOB-TOKEN` is attached only when the next request
   has the exact confirmed GitLab origin, while an external HTTPS object-storage
   URL is fetched without that header. Unsafe, malformed, missing, excessive,
   or unexpected redirects fail closed. The job verifies that the Release points
   to the accepted commit, compares the published checksum file with the
   CI-produced file, checks both hashes, and proves the stable and versioned
   DMGs are byte-identical.

Production jobs are serialized through the
`relux-production-release` resource group. The certificate and API key are
decoded only under a `mktemp` directory; the temporary keychain and decoded
files are removed by an exit trap.

The package upload uses the automatically scoped `CI_JOB_TOKEN`, following the
GitLab Generic Package Registry contract:
<https://docs.gitlab.com/user/packages/generic_packages/>.
Uploads do not follow redirects and require the registry's exact `201` response,
so the custom token cannot be forwarded to another origin.
The GitLab Release exposes the package objects as direct asset links:
<https://docs.gitlab.com/api/releases/links/>.

## Source mirror and tag

Only after the target table is explicit and authorization has been verified:

```bash
git remote add relux-gitlab "git@<CONFIRMED_HOST>:<CONFIRMED_NAMESPACE>/relux-proxy.git"
git ls-remote relux-gitlab
git push --dry-run relux-gitlab "<ACCEPTED_SHA>:refs/heads/main"
git push relux-gitlab "<ACCEPTED_SHA>:refs/heads/main"
git tag -s v0.2.0 "<ACCEPTED_SHA>" -m "Relux Proxy v0.2.0"
git push relux-gitlab v0.2.0
```

Stop if the remote default branch has unrelated history, the dry run names a
different project, the target values disagree, or the protected runner and
variables are absent. Do not force-push around such a mismatch.

The protected tag pipeline publishes exactly:

- `ReluxProxy-v0.2.0-universal.dmg`
- `ReluxProxy.dmg`
- `SHA256SUMS`

The locally configured checkout remains the source of the accepted commit; no
uncommitted working-tree content can enter a tag pipeline.

## Post-release evidence

Keep the successful release and verification job artifacts for audit. They
include the source SHA, architectures, signing authority and team ID,
notarization response and log, Gatekeeper result, and published downloads.

Verify the direct links in the confirmed project:

```text
https://<CONFIRMED_HOST>/<CONFIRMED_NAMESPACE>/relux-proxy/-/releases/v0.2.0/downloads/ReluxProxy-v0.2.0-universal.dmg
https://<CONFIRMED_HOST>/<CONFIRMED_NAMESPACE>/relux-proxy/-/releases/v0.2.0/downloads/ReluxProxy.dmg
https://<CONFIRMED_HOST>/<CONFIRMED_NAMESPACE>/relux-proxy/-/releases/v0.2.0/downloads/SHA256SUMS
```

An unsigned, ad-hoc-signed, unstapled, Gatekeeper-rejected, wrong-host, or
wrong-commit artifact is a failed candidate and must never be described as the
production release.
