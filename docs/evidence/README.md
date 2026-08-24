# Evidence directory

Store only redacted acceptance evidence here. Planned evidence includes:

- local three-server K3s/vCluster status and production smoke (`local-platform-status.md`, `production-smoke-local.md`);
- non-production shared data isolation (`nonprod-data-isolation.md`);
- self-hosted runner controls (`runner-controls.md`);
- Terraform safety boundary (`terraform-safety.md`);
- local recovery backup schedule (`local-backup.md`);
- observability capability mapping (`../observability-splunk-mapping.md`);
- approved local operations (`approved-ops.md`);
- local Pod self-healing and server-stop recovery (`production-pod-resilience.md`, `production-server-failover.md`);
- bounded synthetic order continuity (`synthetic-orders.md`);
- active local Traefik entrypoint (`local-entrypoint.md`);
- production manifest apply and bootstrap-image boundary (`manifest-apply.md`);
- Redis Sentinel and Kafka broker recovery (`production-redis-kafka-resilience.md`);
- DR backup/import status and the Gatekeeper control-plane blocker (`dr-recovery.md`);
- Kafka heap and PostgreSQL degraded/backlog recovery (`kafka-postgres-resilience.md`);
- final CI and Gitleaks/Trivy/Syft/OPA gates ([PR #13](https://github.com/xxseehome/distributed-trading-platform/pull/13), [CI run 32680264540](https://github.com/xxseehome/distributed-trading-platform/actions/runs/32680264540), `github-ci-security-gates.md`);
- PDF、SRE 要求与实现/证据映射（`../acceptance-matrix.md`）；
- Grafana/Prometheus/Loki/Tempo 实际状态与未填充 logs/traces 边界（`observability-status.md`）；
- Terraform plan/apply and identical image digest promotion;
- five environment and DR renders;
- staging Pod replacement resilience test (`resilience.yml`, with approved `KUBECONFIG_B64` and a redacted staging URL);
- CLB health, `/healthz`, market data and order acceptance;
- Grafana SLO, Kafka lag, Redis failover and PostgreSQL projection lag.

Do not store credentials, tokens, private keys, kubeconfigs or unredacted account IDs.
