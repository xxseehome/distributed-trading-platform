# Approved local operations

Mutation paths are separated from read-only monitoring:

- `ops-local.yml` requires a protected-branch `workflow_dispatch`, the exact
  self-hosted runner labels, and the `local-ops` Environment approval before
  kill-switch changes, API restart or consumer resume;
- the kill-switch token is read from the Kubernetes Secret only at execution
  time and is never printed or uploaded;
- `dr-drill-local.yml` separately requires `production-dr` approval for DR
  activation and backup restore;
- all jobs share the local platform concurrency group to prevent overlapping
  mutations.

The operations workflow is a control path; no operation is run automatically
by this local plan.
