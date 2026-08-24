# Non-production shared data isolation

Verified on 2026-08-24 in the local experiment.

The four non-production application overlays (`dev`, `test`, `perf` and
`staging`) do not deploy their own Redis, Kafka or PostgreSQL. Each overlay
points to the single `nonprod-platform` data namespace:

- Redis Sentinel: `redis-sentinel.nonprod-platform.svc.cluster.local`;
- Kafka: `kafka.nonprod-platform.svc.cluster.local:9092`;
- PostgreSQL: `postgres.nonprod-platform.svc.cluster.local`.

Isolation is explicit rather than implicit:

- Kafka topics are created as `<environment>.<topic>` by the shared topic Job;
- each worker uses a matching environment consumer group;
- PostgreSQL uses one schema per environment (`dev`, `test`, `perf`, `staging`);
- the API and Worker overlays set the same `TRADING_SCHEMA` value;
- Redis runtime keys are prefixed with `TRADING_ENV` (or an explicit
  `REDIS_KEY_PREFIX`).

The production overlay remains on its own three-broker Kafka, Redis Sentinel
and PostgreSQL workloads. This keeps the local resource profile small without
claiming production data-plane sharing.

Static verification performed:

```text
kubectl kustomize k8s/overlays/dev          PASS
kubectl kustomize k8s/overlays/test         PASS
kubectl kustomize k8s/overlays/perf         PASS
kubectl kustomize k8s/overlays/staging      PASS
kubectl kustomize k8s/overlays/nonprod-data PASS
```

The non-production vCluster was intentionally left dormant after the Argo CD
registration check; no additional workload replicas were started solely to
produce this evidence.
