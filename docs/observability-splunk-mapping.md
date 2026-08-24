# Observability capability mapping

This local experiment does not deploy Splunk ITSI or Splunk SOAR. The table
maps the demonstrated open-source components to the corresponding enterprise
capabilities so that an operations team can replace the implementation without
changing the operating model.

| Demonstrated local capability | Local component | Splunk ITSI/SOAR analogue | Evidence or boundary |
| --- | --- | --- | --- |
| Service KPI and SLO | Prometheus recording rules and Grafana Trading Overview | ITSI service KPIs, glass tables and service health scores | Low-load experimental SLO only |
| Metrics collection | Prometheus and kube-state-metrics | Splunk metrics indexes and infrastructure monitoring | No Splunk connector is configured |
| Logs | Structured API/Worker JSON logs; Loki is available | Splunk Enterprise log indexes and field extraction | Alloy/log shipping remains a deferred low-resource item |
| Traces | W3C `traceparent` and Tempo datasource | Splunk APM trace/span correlation | The local stack does not claim complete trace ingestion |
| Alert aggregation | Alertmanager PrometheusRules | ITSI notable events and episode review | Alert routing is local-only unless a receiver is configured |
| Incident record | GitHub Incident workflow and diagnostic artifact | Splunk SOAR case/playbook | GitHub remains the local incident system of record |
| Automated response | Approved restart, resilience and DR workflows | SOAR playbook with approval gate | Environment approval is required before mutation |
| Dependency impact | API readiness, Kafka/Redis/PostgreSQL resilience evidence | ITSI service dependency maps and impact analysis | Same-Mac logical clusters are not physical failure domains |

The mapping is an operating-model comparison, not a product equivalence or a
claim that Splunk licensing, collectors or integrations are present.
