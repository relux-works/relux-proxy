# TASK-260728-35ogr2 reviewer verdict

## Verdict

Changes requested. Route to `to-dev`; this is ordinary implementation rework,
not an external blocker.

## Finding

### High: cleanup can retain decoded release credentials on the persistent runner

`.github/workflows/release.yml` enables `set -euo pipefail` in the
`Clean release credentials` step. It calls:

1. `security delete-keychain "$RELEASE_KEYCHAIN"`; then
2. removes `"$RELEASE_TEMP"`.

If `security delete-keychain` returns nonzero, `set -e` exits the step before
the temp-directory removal is attempted. That directory can still contain
`asc.p8`, and the keychain file can still contain the Developer ID private key.
This contradicts `docs/github-release.md`, which says both are deleted by the
`always()` step and that the persistent runner must not retain them between
jobs.

Reviewer failure-path harness evidence:

- simulated `security delete-keychain` exit: `37`
- temp-directory removal attempted: `no`
- simulated keychain remained: `yes`
- simulated `asc.p8` remained: `yes`

Relevant workflow lines at review time: `.github/workflows/release.yml:161`,
`.github/workflows/release.yml:169`, and `.github/workflows/release.yml:176`.
The existing contract test checks only that `always()` and
`security delete-keychain` text are present; it does not cover continuation
after a cleanup subcommand fails.

## Required rework

1. Keep the existing destructive-path guards, but attempt safe keychain
   deletion and safe temp-directory removal independently. Preserve a nonzero
   final cleanup status if either operation fails.
2. Add a regression test for the failure path: when keychain deletion fails,
   temp cleanup must still be attempted so decoded App Store Connect material
   is not retained.
3. Re-run the targeted Swift contract tests, full Swift tests, lint,
   ShellCheck, actionlint, build, remote runner/Xcode smoke, GitHub runner-state
   assertion, tgfs fingerprint assertion, and sanitized secret scan.

## Evidence already verified

- GitHub runner ID 21 is online and idle with exactly `self-hosted`, `macOS`,
  `X64`, and `relux-proxy-release`.
- The existing tgfs runner and LaunchAgent are online/running; all four
  protected tgfs fingerprints match the producer's preflight.
- Full Xcode 26.2 and Swift 6.2.3 resolve on the Intel runner host.
- GitHub repository access is administrative and the four expected secret
  names exist; no secret value was queried.
- The exact-tag/runner/repository/SHA/Xcode/identity preflight failed closed in
  all 16 reviewer negative cases without echoing synthetic secrets.
- Targeted tests passed (4 tests); the full suite passed (55 tests in 10
  suites); Swift lint, ShellCheck, actionlint, build, and whitespace checks
  passed.
- Repository and outcome scans found no private-key, certificate, GitHub token,
  long encoded credential payload, serialized registration-token response, or
  literal registration-token argument.
- No `v0.2.0` Git tag or GitHub Release exists.

No credential values or registration token are included in this verdict.
