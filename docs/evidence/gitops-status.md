# GitOps control-plane status

Verified on 2026-08-24 after PR #22 (`11dbd75dd27f93b0aaa39b284fa836197608955b`):

- Flux source, kustomize, helm and notification controllers: all `1/1`
  Ready;
- Grafana, Prometheus Community and Falco HelmRepositories: `Ready=True`;
- Argo CD server, repo-server, application-controller, Redis, Dex,
  ApplicationSet and notifications controllers: all `1/1` Ready.

Argo CD has three local cluster registrations:

- `production` → `https://kubernetes.default.svc`;
- `non-production` → the `nonprod.vcluster-nonprod` API Service;
- `dr` → the `dr.vcluster-dr` API Service.

The two vCluster registrations use short-lived service-account tokens and
namespace-scoped RoleBindings for `dev`, `test`, `perf`, `staging` and
`production-dr`; no new ClusterRoleBinding or cloud credential is created.
The registration Secrets are runtime-only and are not present in Git.

Argo Application status after the local release restore:

- `trading-production`: `Synced / Healthy` at the merged main revision;
- `trading-production-dr`: `Synced / Progressing`, with all managed resources
  synced and healthy except the intentionally dormant Ingress health check.
  DR keeps application and data workloads at zero replicas and has no active
  Ingress controller, so `Progressing` is an explicit low-resource boundary,
  not a failed sync. It must not be reported as a live DR endpoint.

Production runtime verification also confirmed API, Worker and Frontend at
`3/3` Ready and Kafka at `3/3` Ready after the Kafka startup fix. No
placeholder image is running in Production; the local release remains
protected from Argo image reconciliation by the documented differences.
