# Distributed Trading System Platform

GitHub + 阿里云中国的分布式交易系统运维演示平台，按
[`docs/Plan-Trading-System.md`](docs/Plan-Trading-System.md) 实施。

## 定位

这是一个 Low-Latency Trading Systems Production Operations Lab，用于展示：

- Trading API 的行情、风控、幂等下单和 kill switch；
- Kafka 事件流、Exchange Simulator 和 Worker；
- Redis 热状态与 Sentinel 故障转移；
- PostgreSQL 异步订单/成交/持仓投影；
- K3s、Terraform、Ansible、Flux、Argo CD、GitHub Actions 和可观测性。

不宣称真实交易所接入、真实 FIX 线路、纳秒级 HFT 或 PostgreSQL 数据库 HA。

## 关键数据流

```text
Trading API
  -> Redis risk/idempotency/kill-switch
  -> Kafka acks=all
  -> HTTP 202
  -> Worker / Exchange Simulator
  -> Redis live state + PostgreSQL projection + OSS archive
```

PostgreSQL 不在订单接受关键路径。PostgreSQL 暂时不可用时，订单接收继续，历史查询和异步投影降级，Kafka backlog 在恢复后追平。

## API 演示

```bash
uvicorn backend.main:app --host 0.0.0.0 --port 8000
curl http://127.0.0.1:8000/healthz
curl http://127.0.0.1:8000/readyz
curl http://127.0.0.1:8000/api/market-data/ALPHA
curl -X POST http://127.0.0.1:8000/api/orders \
  -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: demo-1' \
  -d '{"account_id":"demo-account","client_order_id":"client-1","symbol":"ALPHA","side":"BUY","quantity":"2","limit_price":"100.00"}'
```

本地模式使用内存适配器，不伪装成已连接的 Redis、Kafka 或 PostgreSQL；Kubernetes 的 `APP_MODE=cluster` 会在依赖不可用时让 `/readyz` 返回 503。

## 本地验证

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r backend/requirements-dev.txt
pytest -q
ruff check .
ruff format --check .
for env in dev test perf staging production production-dr nonprod-data; do
  kubectl kustomize "k8s/overlays/$env" >/tmp/render-$env.yaml
done
```

Kubernetes 清单包含五个应用环境和北京 DR；dev/test/perf/staging 共享
`nonprod-platform` 数据平面，并用 Kafka topic 前缀和 PostgreSQL schema 隔离。
Production 使用三副本 Trading API/Worker、三 broker Kafka、Redis Sentinel
和单 PostgreSQL primary。

## 资源边界

- 三个 K3s 集群：杭州 non-production、杭州 production、北京 DR；
- Production 三个跨可用区 K3s server；DR 为单节点温备；
- PostgreSQL、Redis 和 Kafka 作为 K3s 工作负载，不创建 RDS 或其他托管数据库；
- 未完成 GitHub OIDC、阿里云试用额度和成本门禁前，不创建云资源；
- 不管理旧 Online Book Store 资源。
