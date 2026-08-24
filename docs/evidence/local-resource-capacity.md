# 六环境本地资源容量核验

核验日期：2026-08-24。只读检查，不修改 Docker 或 Kubernetes。

## 当前资源

| 项目 | 实测值 | 结论 |
|---|---:|---|
| Docker Desktop CPU | 12 vCPU | CPU 充足 |
| Docker Desktop memory limit | 7.65 GiB | 内存是主要瓶颈 |
| Kubernetes Pod memory requests | 7.39 GiB | 已接近 Docker 上限 |
| Kubernetes Pod CPU requests | 3.415 cores | 当前 CPU requests 充足 |
| PVC requests | 38 GiB / 16 PVC | 磁盘容量充足；PVC 仍会占用 Docker volume |
| 主机根盘可用空间 | 约 677 GiB | 磁盘不是当前瓶颈 |
| 运行时 memory usage | 约 7.06 GiB（3 个逻辑节点合计） | 不应再并行启动大量副本 |

三个 Kubernetes node 都显示约 7.65 GiB，这是同一个 Docker Desktop VM 的容器视图，不能相加为 22.9 GiB 的真实主机内存。

## 六个逻辑目标

- non-production vCluster：`dev`、`test`、`perf`、`staging` namespace 均存在；当前只运行 vCluster 宿主和 CoreDNS，应用 workload 尚未启动。
- production cluster：`production` workload 正常运行，API/Worker/Frontend 各 3 副本，数据服务和监控正常。
- DR vCluster：`production-dr` namespace 存在；应用和数据 StatefulSet 当前为 0 副本，保持温备。

## 全量并行边界

按当前 manifest requests 粗算，四个 non-production 应用约需 1.88 GiB，non-production 共享数据服务约需 1.00 GiB，DR 从 0 副本启动约需 1.31 GiB。若六个目标全部同时运行，预计 Pod requests 约为 `7.39 + 4.19 = 11.58 GiB`，超过 Docker Desktop 的 7.65 GiB 限制，可能导致 Pending、驱逐或 OOM。

因此当前可支持：

1. 六个环境的 namespace、vCluster、GitHub Environment 和串行推广逻辑；
2. production 全量运行，non-production 按环境串行验证；
3. DR 按演练启动，完成后恢复为 0 副本。

当前不支持：

- 六个环境的全部应用和数据服务长期同时运行；
- 把三个 k3d server 当作三台独立物理主机或三个可用区；
- 在不增加 Docker 内存或降低监控/副本的情况下启用完整 Alloy、exporter 和全量 DR。

