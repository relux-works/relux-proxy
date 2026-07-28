# TASK-260728-2mjju4 logbook

## 2026-07-28 — independent tester validation

- Deterministic controller fixtures reproduced two simultaneous process/session
  lifecycles on distinct loopback ports. Failure and stop transitions remained
  isolated to the selected profile.
- Static and runtime tests confirmed that IP addresses, hostnames, and OpenSSH
  aliases are passed to `/usr/bin/ssh` as array arguments. Account overrides use
  `-l <account>` and shell metacharacters remain literal; no shell command line
  is constructed.
- The affected non-UI tunnel code reached 92.01% line coverage. Whole-executable
  coverage is lower because the SwiftUI view and app entry bodies are outside
  this unit/local-integration matrix.
- The default `make app` invocation found the local Developer ID and signed the
  local validation build. No release was published or notarized. The retained
  `dist/ReluxProxy.app` was rebuilt with `SIGN_IDENTITY=-` and independently
  verified as an ad-hoc-signed universal bundle, preserving the task's
  no-release-signing boundary.
- The only unexecuted acceptance step is physical exit-identity verification
  through two authorized external SSH hosts. No such hosts or authorized
  identity endpoint were supplied, so the exact two-port procedure is recorded
  in `README.md` and deliberately excluded from automation.
- No implementation regression or unresolved architecture/product constraint
  was found.
