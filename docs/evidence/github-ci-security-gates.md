# GitHub CI 与安全门禁

验证日期：2026-08-24

- PR：[#22](https://github.com/xxseehome/distributed-trading-platform/pull/22)
- 合并提交：`11dbd75dd27f93b0aaa39b284fa836197608955b`
- CI run：[CI and security gates #32693613787](https://github.com/xxseehome/distributed-trading-platform/actions/runs/32693613787)
- 计划同步：[Plan synchronization #32693613771](https://github.com/xxseehome/distributed-trading-platform/actions/runs/32693613771)

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
