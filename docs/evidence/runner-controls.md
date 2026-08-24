# Self-hosted runner controls

Verified on 2026-08-24 by parsing all local deployment and drill workflows.

- `local-platform`, `promote-local`, `resilience-local`, `dr-drill-local`
  and `incident-monitor-local` use the exact runner labels
  `[self-hosted, macOS, ARM64, trading-local-arm64]`;
- each self-hosted job is `workflow_dispatch` only and has an explicit
  `github.ref_protected == true` guard;
- no local self-hosted workflow uses `pull_request_target`;
- promotion and destructive/drill workflows retain GitHub Environment gates;
- the hosted CI/build workflows remain separate from the local runner.

This is repository-side enforcement. The GitHub repository's branch rules and
Environment required-reviewer settings remain external configuration and must
be kept enabled.
