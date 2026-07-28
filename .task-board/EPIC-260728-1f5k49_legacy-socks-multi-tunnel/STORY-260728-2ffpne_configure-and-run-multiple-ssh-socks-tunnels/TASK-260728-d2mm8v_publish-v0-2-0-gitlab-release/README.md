# TASK-260728-d2mm8v: publish-v0-2-0-gitlab-release

## Description
Prepare and publish the accepted multi-tunnel application as Relux Proxy v0.2.0 in the confirmed Relux GitLab project, without using unrelated GitLab instances or leaking signing credentials.

## Scope
Add or adapt GitLab CI release automation for a macOS runner; mirror/push the accepted source to the confirmed project; build the universal app and DMG; Developer ID sign, notarize, staple, Gatekeeper-validate, checksum, tag v0.2.0, and create a GitLab Release with versioned and stable-name assets. The exact GitLab project and authorization must be confirmed or discovered before any external push. Excludes publishing to gitlab.wildberries.ru and excludes changing the accepted feature after release review.

## Acceptance Criteria
1. The target GitLab hostname, namespace, and repository are explicitly confirmed as the Relux project before remote mutation. 2. GitLab CI or an equivalent auditable release path uses masked credentials and a trusted macOS runner to build, sign, notarize, staple, and validate the universal DMG. 3. v0.2.0 is created from the accepted commit and the GitLab Release exposes ReluxProxy-v0.2.0-universal.dmg, ReluxProxy.dmg, and SHA256SUMS. 4. Published hashes match locally or CI-produced artifacts and release notes describe multi-profile SSH alias behavior and concurrent local SOCKS endpoints. 5. Missing GitLab project access, runner, Developer ID, or notarization credentials becomes an exact evidence-backed external blocker; no unrelated host or unsigned artifact is represented as the production release.
