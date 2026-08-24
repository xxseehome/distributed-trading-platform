# Local observability stack

The local stack is intentionally self-hosted inside the production k3d cluster.
It does not use Grafana Cloud, Splunk, or any paid cloud service.

Components:

- `kube-prometheus-stack`: Prometheus, Alertmanager, Grafana, kube-state-metrics and node exporter.
- Loki monolithic mode for short-retention logs.
- Tempo monolithic mode for short-retention traces.
- Grafana is provisioned with the Prometheus, Loki and Tempo data sources and a
  local Trading Overview dashboard. The pinned chart's built-in Kubernetes
  dashboards remain enabled.

Deferred low-resource extensions:

- Grafana Alloy for OTLP, Kubernetes logs and Prometheus scraping is not
  deployed in the minimal profile, so Loki/Tempo are available for later
  ingestion but the current smoke evidence does not claim application logs or
  traces are flowing into them.
- Kafka, Redis and PostgreSQL exporters and blackbox exporter are not deployed;
  their dashboards/alerts remain a documented extension rather than a false
  runtime claim.

Resource and retention limits:

- Prometheus: 2 GiB PVC, 6 hours retention.
- Loki: 2 GiB PVC, 6 hours retention.
- Tempo: 1 GiB PVC, 6 hours retention.
- Grafana: 1 GiB PVC.
- The total observability memory request must remain below 3 GiB.

Install with the pinned Helm chart versions from the local platform workflow.
The chart values in this directory are the reviewed source of truth; the workflow
must never use `latest` chart or image tags.

Docker Desktop/k3d does not prove host-level eBPF telemetry. Falco is retained
for static policy and synthetic-event demonstrations only.

## Image download note

The Singapore VPN can accelerate host-side downloads, but Docker Desktop runs
the Kubernetes nodes inside its own VM and does not automatically inherit the
host VPN route. The local bootstrap therefore prefers verified domestic
mirrors and imports the resulting images into each k3d server. A component is
not marked healthy until its Pod is Ready; a mirror timeout is recorded in
`docs/evidence/observability-status.md` rather than hidden.
