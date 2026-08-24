# Local GitOps ownership

The local experiment keeps a strict ownership boundary:

| Layer | Owner | Scope |
| --- | --- | --- |
| Platform | Flux | namespaces, Gatekeeper, Falco, observability and the Argo CD installation |
| Applications | Argo CD | frontend, trading-api, trading-worker, Redis, Kafka and PostgreSQL |
| Release promotion | GitHub Actions | writes the immutable image digests and selected environment state; it does not edit live resources outside the approved runner |

The production k3d cluster is the host context.  `vcluster-nonprod` and
`vcluster-dr` are separate logical Kubernetes API servers hosted by it.  The
GitOps controller is not allowed to manage the same object from both layers.

The local manifests deliberately use repository-relative paths and immutable
image digests supplied by `release.json`; they do not contain credentials or
cloud-provider resources.

Argo CD cluster registrations are refreshed at runtime by
`scripts/register-local-argocd-clusters.sh`. The production registration uses
the existing Argo controller identity; non-production and DR use short-lived
service-account tokens with namespace-scoped `admin` RoleBindings only. Tokens
are stored only in Argo CD's local cluster Secrets and are never committed or
uploaded as evidence. The vCluster API CA is carried in the Secret so the
registration does not disable TLS verification.
