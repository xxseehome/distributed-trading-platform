# Local API smoke test

Executed against the local FastAPI process on 2026-08-23 using the simulated
adapter mode (no external Redis/Kafka/PostgreSQL credentials):

```text
/healthz                 200
/readyz                  200
/metrics                 200
/api/market-data/ALPHA   200
POST /api/orders         202 Accepted
```

The order request used a synthetic account and idempotency key. No secret or
real market data was used.
