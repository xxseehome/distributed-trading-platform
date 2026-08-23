# Evidence directory

Store only redacted acceptance evidence here. Planned evidence includes:

- final CI and Gitleaks/Trivy/OPA gates (PR #8 / [main run 32610037141](https://github.com/xxseehome/distributed-trading-platform/actions/runs/32610037141));
- Terraform plan/apply and identical image digest promotion;
- five environment and DR renders;
- staging Pod replacement resilience test (`resilience.yml`, with approved `KUBECONFIG_B64` and a redacted staging URL);
- CLB health, `/healthz`, market data and order acceptance;
- Grafana SLO, Kafka lag, Redis failover and PostgreSQL projection lag.

Do not store credentials, tokens, private keys, kubeconfigs or unredacted account IDs.
