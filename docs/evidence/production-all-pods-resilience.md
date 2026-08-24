# Production all-workload Pod resilience

Verified on 2026-08-24 in the local `trading-production` k3d cluster.

The approved local resilience scenario deleted one running Pod from each of
`frontend`, `trading-api` and `trading-worker` without stopping a server or
deleting a volume. During replacement it issued 20 low-load checks against
the Traefik route:

```text
GET /healthz: 20/20 HTTP 200
GET /:        20/20 HTTP 200
HTTP failures: 0
frontend:     Ready 3/3
trading-api:  Ready 3/3
trading-worker: Ready 3/3
```

This verifies in-node workload self-healing only. It does not prove recovery
from a Docker Desktop, Mac, physical node or availability-zone failure.
