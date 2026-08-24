# Production manifest apply evidence

On 2026-08-24 the production overlay was reapplied locally after adding the
localhost Ingress fallback. The production anti-affinity patch was corrected
to use the Kubernetes-required `podAffinityTerm` structure; a subsequent
apply completed without schema errors.

The raw overlay contains `registry.invalid/...:bootstrap` placeholders. A
direct apply briefly created ImagePullBackOff replacement Pods, so the last
known-good local images were restored immediately:

```text
frontend       local/trading-frontend:dev
trading-api    local/trading-api:recovery2
trading-worker local/trading-api:recovery2
```

Final state:

```text
frontend       3/3
trading-api    3/3
trading-worker 3/3
Kafka          3/3
Redis          3/3
PostgreSQL     1/1
GET /          200
GET /healthz   200
GET /api/market-data/ALPHA  200
```

Future local promotion must use `scripts/local-promote.sh`, which substitutes
the immutable local release images before applying workload manifests.
