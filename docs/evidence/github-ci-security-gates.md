# GitHub CI 与安全门禁

验证日期：2026-08-24

- PR：[#13](https://github.com/xxseehome/distributed-trading-platform/pull/13)
- 提交：`454d00af195498b42528ce7b2095a369fd06da8a`
- CI run：[CI and security gates #32680264540](https://github.com/xxseehome/distributed-trading-platform/actions/runs/32680264540)
- 计划同步：[Plan synchronization #32680264543](https://github.com/xxseehome/distributed-trading-platform/actions/runs/32680264543)

两次运行均为 `success`。CI 门禁通过：

- Gitleaks
- Trivy filesystem scan
- Trivy configuration scan
- Syft SBOM
- OPA and Conftest
- Ruff、pytest、integration
- Terraform validation and plan-only
- Docker build gate

本证据只证明 GitHub-hosted CI 对当前提交通过；不代表已创建或变更阿里云资源。

