# Production API Pod resilience and order continuity

Verified on 2026-08-24 in the local `trading-production` k3d cluster.

## Scenario

- One running `trading-api` Pod was deleted with `ALLOW_LOCAL_FAULT=true`.
- No K3s server, database, PVC, Docker cluster or cloud resource was stopped
  or deleted.
- A 30-second synthetic order stream ran concurrently at a two-second interval
  through the Traefik entrypoint.

## Result

```text
deleted Pod: trading-api-79bc656dfd-f9l2s
synthetic attempts: 12
accepted: 12
failed: 0
deployment rollout: successfully rolled out
final trading-api: 3/3 Ready
```

The replacement Pod became Ready on another local k3d server. The result proves
workload-level self-healing and order continuity inside the local cluster; it
does not prove physical-node or cloud-region failover.
