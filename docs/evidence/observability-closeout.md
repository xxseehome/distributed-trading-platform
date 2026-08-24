# Observability closeout evidence

Verified on 2026-08-24 in the local `trading-production` k3d cluster after the
API Pod resilience drill.

## Metrics, lag and alerting

- Prometheus: Ready; all three `trading-api` ServiceMonitor targets returned
  `up=1` after the network policy allowed Prometheus to reach port 8000.
- `trading_orders_accepted_total` was present for all three API Pods after the
  12 accepted synthetic orders.
- Kafka `production-projection` consumer group had lag `0` for both
  `production.orders.accepted.v1` and `production.executions.v1` partitions.
- Alertmanager: Ready; the API target-down alerts cleared after recovery.
  Baseline local-k3d alerts (for example missing kube-proxy metrics and node
  clock/IO warnings) remain visible and are not suppressed.
- PrometheusRule `trading-slo-rules` is present with availability, latency and
  API target-down rules.

## Logs and traces boundary

- Application logs are available through `kubectl logs`; the resilience run
  recorded Uvicorn health checks and `POST /api/orders` responses.
- Loki is Ready, but its label endpoint currently returns an empty label set:
  no log shipper (Alloy/Promtail) is deployed in the minimal profile.
- Tempo is Ready, but no application spans are present: the application
  propagates `traceparent` and does not yet export OpenTelemetry spans.

These are honest capability boundaries, not synthetic success claims. Adding a
log collector and OpenTelemetry SDK/exporter would be a separate resource and
code change.

## Incident record

The hosted GitHub Incident workflow completed successfully and created [Issue
#18](https://github.com/xxseehome/distributed-trading-platform/issues/18) for
the Pod replacement drill. The issue is a drill record; it is not evidence of
an automatically triggered Alertmanager-to-GitHub integration.
