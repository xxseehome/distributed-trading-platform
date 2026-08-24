# PDF 与附加 SRE 要求验收矩阵（本地实验版）

本矩阵把 `docs/Plan-Trading-System.md` 中从测试 PDF 和附加 SRE/可观测性要求提取的验收项，映射到当前本地实现与证据。它描述的是一台 Mac 上的低资源实验，不把本地逻辑集群写成真实云集群或跨可用区 HA。

状态：

- ✅ 已实现并有证据
- ⚠️ 已有配置或部分验证，但仍有明确边界
- ⏸️ 因无云凭据/成本约束跳过

| 要求 | 当前实现 | 证据 | 状态与边界 |
|---|---|---|---|
| 多层应用 | Nginx Frontend、Trading API、Worker、Redis、Kafka、PostgreSQL | `docs/architecture.md`、`docs/evidence/production-smoke-local.md` | ✅ |
| 订单、风控、幂等和异步投影 | Decimal、Idempotency-Key、Kafka `acks=all`、Worker 去重、PostgreSQL projection | `docs/evidence/api-smoke-local.md`、`docs/evidence/kafka-postgres-resilience.md` | ✅ |
| 容器化与 Kubernetes | Docker 镜像、k3d 三 server、non-production/production/DR vCluster | `docs/evidence/local-platform-status.md` | ✅ 逻辑集群；不是三台物理主机 |
| Production HA | embedded etcd quorum、三副本 API/Worker、Kafka/Redis 故障演练 | `docs/evidence/production-server-failover.md`、`production-redis-kafka-resilience.md` | ✅ 本地故障域；不等同跨 AZ |
| Infrastructure as Code | Terraform fmt、validate、隔离 backend plan-only | `docs/evidence/terraform-safety.md`、CI run [32680764860](https://github.com/xxseehome/distributed-trading-platform/actions/runs/32680764860) | ✅ 未执行 apply |
| GitHub CI/CD | PR、Branch Protection、Environments、Ruff/pytest/integration、Build gate | [PR #13](https://github.com/xxseehome/distributed-trading-platform/pull/13) | ✅ 已 squash 合并 |
| 代码与供应链安全 | Gitleaks、Trivy filesystem/config、Syft SBOM、OPA/Conftest | `docs/evidence/github-ci-security-gates.md` | ✅ GitHub-hosted CI |
| 不可变镜像 | Cosign 签名、同一 commit/digest 的 build/promote 工作流 | `.github/workflows/build-promote.yml`、`docs/plan-local-trading-system.md` | ⚠️ 六环境运行证据尚缺 |
| GitOps | Flux 与 Argo CD 清单、cluster contexts、分层 Kustomize | `docs/evidence/gitops-status.md` | ⚠️ 未宣称两者均 Healthy/Synced |
| 可观测性 | Prometheus、Loki、Tempo、ServiceMonitor、SLO/告警规则 | `docs/evidence/observability-status.md` | ⚠️ Alloy/exporter/完整 traces 链未完成 |
| SRE 故障恢复 | Pod 自愈、server stop、Redis Sentinel、Kafka broker、PostgreSQL degraded/backlog、DR restore | `docs/evidence/production-*.md`、`docs/evidence/dr-recovery.md` | ✅ 有界低负载演练 |
| 备份与恢复 | 15 分钟备份工作流、压缩 pg_dump、Kafka 元数据、DR restore | `docs/evidence/local-backup.md`、`.github/workflows/backup-local.yml` | ⚠️ artifact 工作流已配置，尚未由 self-hosted runner 实跑 |
| 事件响应与审批 | local-ops、DR activation、Incident workflow、Environment approval | `docs/evidence/approved-ops.md`、`docs/observability-splunk-mapping.md` | ⚠️ 未宣称端到端告警自动触发 |
| 云平台交付 | 阿里云 VPC/ECS/CLB/ACR/OSS、真实三集群、跨 AZ/地域 DR | 原始云架构保留在 `docs/Plan-Trading-System.md` | ⏸️ 按预算和用户要求不创建/不 apply |
| 验收材料 | Mermaid 架构图、运行日志、健康接口、故障演练和 CI 链接 | `docs/architecture.md`、`docs/evidence/` | ✅ 文字证据；PNG/完整 Grafana 截图仍待补充 |

## 结论

当前仓库满足“可复现的本地 Distributed System/SRE 实验”和 GitHub 免费 CI 安全门禁的验收范围。必须在面试材料中明确：真实阿里云三集群、跨可用区/跨地域故障切换、云端 CLB/ACR/OSS、完整 Grafana Cloud 链路和六环境运行证据未在本次预算约束下宣称完成。

