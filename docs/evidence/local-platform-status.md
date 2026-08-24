# Local platform status

Collected during the local execution on 2026-08-24. No cloud resource or
credential is included.

```text
k3d cluster: trading-production
servers: 3/3, agents: 0/0, loadbalancer: true
nodes: k3d-trading-production-server-0/1/2 Ready
Kubernetes: v1.31.6+k3s1
zones: local-a, local-b, local-c
vCluster: nonprod Running (vcluster-nonprod)
vCluster: dr Running (vcluster-dr); production-dr workloads dormant (0 replicas)
```

API access checks passed through the production kubeconfig and the two
`vcluster connect ... -- kubectl get nodes` paths. The production API returned
three Ready nodes; each virtual API returned its own Ready virtual node.

Active namespaces include `production`, `observability`, `flux-system`,
`argocd`, `gatekeeper-system`, `vcluster-nonprod`, and `vcluster-dr`.

Argo CD runtime registrations were refreshed for `production`,
`non-production` and `dr`; vCluster credentials are short-lived and stored
only as local Argo CD Secrets. The registration details are in
`gitops-status.md`.

The DR restore drill completed from the validated PostgreSQL backup and left
the three DR data PVCs Bound after scaling the application and data workloads
back to zero. Details and the intentionally unclaimed RPO limitation are in
`dr-recovery.md`.

The three logical clusters share one Docker Desktop host; they are not three
physical failure domains.

Production workload verification after the local recovery:

```text
trading-api      3/3 Ready
trading-worker   3/3 Ready
frontend         3/3 Ready
redis            3/3 Ready
redis-sentinel   3/3 Ready
kafka            3/3 Ready
postgres         1/1 Ready
```

The Docker addresses are dynamic. During recovery experiments, stale etcd
peer records were corrected to the current container address (server-0 was
restored at `172.18.0.2`; server-2 later restarted at `172.18.0.3`); no etcd
member or data was deleted. All three K3s servers then returned to `Ready`.
The detailed server-stop result, including the local load-balancer timeout
limitation, is recorded in `production-server-failover.md`.

Measured from the running host cluster:

```text
Pod memory requests: 7180 MiB total (all running containers, including
Gatekeeper and vCluster control planes)
Observability requests: 1024 MiB
PVC requests: 17 GiB
```

These values are below the plan's 10 GiB total Pod-request, 3 GiB
observability-request, and 50 GiB PVC limits.

Docker Desktop currently advertises 12 host CPUs and 7.65 GiB memory to the
daemon. The plan's optional 16 GiB Docker memory target cannot be applied to
this Mac, whose physical memory is about 8 GiB; the local experiment keeps the
measured limits above rather than overcommitting the host.
