# TASK-260728-3iwief developer logbook

## 2026-07-28

- Read the prior independent reviewer verdict and reproduced its finding: the
  verifier used a browser permanent-link release route with a job token.
- Confirmed from GitLab’s official Releases API documentation that JOB-TOKEN
  is supported on the API asset-download route, not assumed for the browser
  route.
- Replaced the verifier’s direct-download base with the exact Releases API
  base, added a regression that rejects /-/releases/ in the verifier, and
  documented the CI/end-user route distinction.
- Re-ran shell lint/syntax, YAML parse, Swift formatting, 49 Swift tests,
  Swift build, and an isolated universal ad-hoc app build.
- Ran one positive and twelve expected-negative preflight contexts. Ran
  synthetic offline upload/verification positives and fail-closed negative
  cases with a task-local curl stub; no external request was attempted.
- Verified no secret values were printed, no shell tracing was enabled, no
  local v0.2.0 tag exists, and the only checked remote remains the expected
  GitHub origin.
