# TASK-260728-35ogr2: configure-relux-github-release-runner

## Description
Configure a dedicated GitHub Actions self-hosted macOS runner for relux-works/relux-proxy on the machine reached by ssh alias relux and bind the v0.2.0 release workflow to it without disrupting the existing relux-works/tgfs runner.

## Scope
Install or register a second runner in a separate directory and service; use a unique relux-proxy-release label; select full Xcode; update workflow tests and runbook for GitHub self-hosted release. Do not create the v0.2.0 tag or Release in this task. Preserve all unrelated dirty worktree changes and the existing tgfs runner.

## Acceptance Criteria
GitHub lists an online idle runner assigned to relux-works/relux-proxy with self-hosted macOS x64 relux-proxy-release labels; the existing tgfs service remains running and unchanged; release.yml targets only the dedicated label and fail-closes on missing release identity; Swift tests shell lint workflow validation and a remote runner smoke pass; task-scoped evidence contains sanitized runner state with no registration token or secret values.
