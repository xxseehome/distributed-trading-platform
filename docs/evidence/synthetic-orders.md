# Bounded synthetic-order evidence

Collected on 2026-08-24 against the local Docker Desktop/k3d production
entrypoint. The run used only synthetic account and order identifiers; it did
not contact a real exchange, cloud service, or external market feed.

```text
route: http://127.0.0.1:8080
Host: bookstore.example.invalid
duration_seconds=30
interval_seconds=5
attempts=6
accepted=6
failed=0
```

This is a bounded low-load continuity check, not a claim of an always-on
load generator or production throughput capacity. The script is
`scripts/local-synthetic-orders.sh` and exits non-zero if any request is not
HTTP 202.
