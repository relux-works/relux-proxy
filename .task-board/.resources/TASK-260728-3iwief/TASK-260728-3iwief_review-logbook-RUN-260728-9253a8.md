# TASK-260728-3iwief review logbook — RUN-260728-9253a8

## 2026-07-28

- Confirmed the run is not goal-bound and received no operator directives.
- Read the prior reviewer verdict and developer rework artifact before beginning
  a fresh source audit.
- Fingerprinted the pre-existing dirty worktree outside board/temp, created a
  task-scoped source snapshot, and verified the snapshot matched the source.
- Confirmed the prior endpoint defect is fixed: verification now uses
  `CI_API_V4_URL/projects/$CI_PROJECT_ID/releases/$CI_COMMIT_TAG/downloads`.
- Cross-checked Releases API job-token authentication, the direct-asset route,
  Generic Package Registry uploads, release-link redirect behavior, and Apple's
  notarization sequence against current primary documentation.
- Reproduced all shell, YAML, Swift format/test/build, universal app-build,
  preflight, signing, upload, and verification gates locally.
- Found and locally reproduced a new credential-boundary defect: curl forwards
  the custom `JOB-TOKEN` header through `--location` to a redirected origin.
  GitLab allows release links to point externally and always redirects direct
  links, so post-download hashes cannot prevent the token disclosure.
- Used only a synthetic token, loopback servers, and an exported curl stub. No
  external GitLab or Apple mutation was attempted.
- Verified the source/worktree fingerprint remained unchanged and routed the
  finding as ordinary implementation rework, not `blocked`.
