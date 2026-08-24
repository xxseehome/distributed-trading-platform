# Local DR recovery evidence

## Result

The local DR drill completed on 2026-08-24 without changing cloud resources.
The control-plane failure was fixed at the vCluster chart boundary: the
`vcluster-dr/dr-0` syncer now has explicit CPU and memory requests/limits, so
the existing Gatekeeper `trading-pod-baseline` constraint remains enabled and
passes. No platform namespace exception was added.

The vCluster `rewrite-hosts` init container was also set to the already-cached
`redis:7.4-alpine` image. This avoids downloading `library/alpine:3.20` on the
local nodes and keeps the drill reproducible when the network is slow.

## Recovery run

- Backup: `.runtime/backups/postgres-20260823T142918Z.sql.gz` (gzip validated,
  mode `0600`)
- Release metadata: `.runtime/local-release.json`
- DR image set: `local/trading-api:recovery2` and `local/trading-frontend:dev`
- DR control plane: vCluster `0.24.0`, K3s `v1.31.6-k3s1`
- DR data services: Redis, Redis Sentinel, single Kafka broker, PostgreSQL
- Single-broker Kafka overlay sets offsets/transaction-state replication to 1;
  production remains on its three-broker configuration.
- PostgreSQL schema was dropped and the gzip SQL stream was imported before
  application replicas were started.

Observed results during the completed run:

- PostgreSQL core table counts after import: `orders=5`, `executions=5`,
  `positions=5`, `processed_events=10`.
- API `/healthz`, `/readyz`, and `/metrics`: HTTP `200`.
- Frontend, Trading API, Worker, Redis, Redis Sentinel, Kafka, and PostgreSQL:
  all `1/1 Ready` during the active drill.
- The script injected the release commit and API/frontend image digests into
  the DR deployments; credentials remained Kubernetes Secret data and were not
  written to Git, logs, or artifacts.
- After verification, all DR Deployments and StatefulSets were scaled back to
  `0`; the three data PVCs remain `Bound`.

The follow-up business-interface run on 2026-08-24 restored the same backup,
started the same release and verified:

```text
GET /healthz                  200
GET /readyz                   200
GET /metrics                  200
GET /api/market-data/ALPHA    200
POST /api/orders              202
GET /api/orders/{new-order}   200 (after Worker projection)
GET /api/positions/{account}  200
```

The script now scales the DR Deployments and StatefulSets back to zero in its
exit cleanup; the application and data PVCs stay `Bound`.

## Limits

This is a same-Mac vCluster recovery exercise. It demonstrates the backup,
restore, GitOps activation, health checks, and cleanup path, but it does not
prove a separate-region, separate-host, or node-level DR objective. The backup
used for this run was a local artifact rather than a scheduled 15-minute
backup, so an RPO `≤15 minutes` claim is intentionally not made.
