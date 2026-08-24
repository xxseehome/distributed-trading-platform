# Production server failover evidence

Collected during the local execution on 2026-08-23. The experiment stopped
and restarted `k3d-trading-production-server-2`; it did not delete the k3d
cluster or any volume.

## What passed

```text
etcd members after recovery: 3/3 started
K3s nodes after recovery: 3/3 Ready
Production workloads after recovery: API 3/3, Worker 3/3, Frontend 3/3
Kafka 3/3, Redis 3/3, PostgreSQL 1/1
```

The restarted Docker container received a new dynamic IP (`172.18.0.3`
instead of its previous `172.18.0.5`). The embedded etcd member peer URL was
updated to the current address without removing the member or changing data.

The stopped-server window retained embedded-etcd quorum (2 of 3 members); the
cluster returned to 3 of 3 started members after the container was restored.
This is the evidence for the plan items covering a reversible one-server stop
and quorum preservation.

## Limitation observed

During the 30-second stop window, 30 health requests through the k3d Docker
load balancer produced 14 timeouts. The remaining nodes retained etcd quorum,
but the local load balancer continued to select the stopped container until
the node was restored. Therefore this run is **not** evidence of zero-downtime
server failover. It demonstrates recoverability of the logical three-server
cluster, not production-grade node failover or a physical failure domain.
