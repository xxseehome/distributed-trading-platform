# Local observability status

Collected during the local execution on 2026-08-23. Retention and PVC sizes
remain bounded by the reviewed Helm values.

Running components:

- Prometheus and config reloader: `2/2` Ready;
- Alertmanager: `2/2` Ready;
- Prometheus Operator: `1/1` Ready;
- node-exporter: three Ready Pods, one per local zone;
- Grafana: `1/1` Ready with a 1 GiB PVC; the deployment has the dashboard
  sidecar, datasource sidecar and Grafana containers;
- kube-state-metrics: `1/1` Ready (imported through the verified local image
  path; container image ID `sha256:fa14cab93b114de896a8c61a3f3d8e522bc25615da624c7a5db14e496b616055`);
- Loki monolithic: `1/1` Ready;
- Tempo monolithic: `1/1` Ready.

Flux HelmReleases are Ready after the bounded timeout/remediation settings:

- `kube-prometheus-stack` revision `6`;
- `loki` revision `3`;
- `tempo` revision `2`.

Business monitoring objects are active:

- `ServiceMonitor/observability/trading-api` discovers all three production API
  Pods; Prometheus returned three `up{job="trading-api",namespace="production"}`
  series with value `1`.
- `PrometheusRule/observability/trading-slo-rules` is loaded with availability,
  p95 acceptance latency and target-down alerts.
- Grafana contains `Trading Overview` (`trading-overview-local`) and the
  Prometheus, Loki and Tempo data sources (`prometheus`, `loki`, `tempo`).

Not yet deployed in this minimal local profile:

- Grafana Alloy;
- blackbox exporter;
- Kafka, Redis and PostgreSQL exporters.

The Singapore VPN is available to host tools, but Docker Desktop's VM does
not automatically inherit that route. Domestic mirrors and locally imported
images were used where available. The exporter omissions are intentional to
keep the local experiment within the memory budget; Prometheus, Alertmanager,
Grafana, Loki, Tempo, node-exporter and kube-state-metrics are healthy.

## Grafana API verification (2026-08-24)

The local Grafana service was port-forwarded temporarily and queried with the
runtime Kubernetes Secret; no credential value was printed or saved.

- `/api/health` returned HTTP 200, Grafana `11.6.0`, database `ok`.
- `Trading Overview` (`trading-overview-local`) exists with six panels.
- Prometheus, Loki, Tempo and Alertmanager data sources are registered.
- A Prometheus query for `up{job="trading-api",namespace="production"}` returned
  three series.
- Loki returned an empty label set and Tempo returned zero traces during this
  low-traffic check; therefore this is evidence of configured data sources and
  metrics retrieval, not evidence of populated log/trace history.
