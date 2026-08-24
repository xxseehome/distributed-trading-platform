# GitOps control-plane status

Verified on 2026-08-24:

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

The Argo Applications are intentionally still OutOfSync/Missing until an
immutable application release manifest is available; no placeholder image is
deployed into the cluster.
