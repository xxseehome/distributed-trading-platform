# Production API Pod self-healing evidence

Collected on 2026-08-23 in the local `trading-production` k3d cluster.

Scenario: delete one running `trading-api` Pod only. No K3s server, database,
PVC, or cloud resource was stopped or deleted.

```text
deleted: trading-api-567dc87c89-5sc2r
HTTP health checks during replacement: 20
HTTP failures: 0
Deployment rollout: successfully rolled out
Final trading-api: 3/3 Ready
```

The replacement Pod was scheduled on the missing server zone and the
Traefik-backed `/healthz` route remained HTTP 200 throughout the 20-request
low-load window.
