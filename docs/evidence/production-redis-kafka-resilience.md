# Production Redis and Kafka resilience evidence

Collected during the local execution on 2026-08-23. These are reversible Pod
deletion drills in the three-server k3d cluster; no PVC or configuration was
deleted.

## Redis Sentinel

- Before the drill, Sentinel reported `redis-0` (`10.42.3.76:6379`) as the
  `mymaster` address.
- `redis-0` was deleted and StatefulSet recovery completed.
- Sentinel elected `10.42.3.97:6379` as the new master; `redis-0`, `redis-1`
  and `redis-2` returned `Ready`.
- One health request timed out during election. After recovery a synthetic
  `ALPHA` order returned HTTP `202` (`redis-failover-20260823`).

## Kafka

- Before the drill, `kafka-0`, `kafka-1` and `kafka-2` were Ready.
- `kafka-0` was deleted; the StatefulSet recreated it on the same local
  cluster and all three brokers returned Ready.
- Twenty ingress health checks recorded two short timeouts while the broker
  restarted; a synthetic `BETA` order returned HTTP `202`
  (`kafka-failover-20260823`). RF=3 and `min.insync.replicas=2` therefore kept
  the order-acceptance path available after broker recovery, but this local
  ingress path is not a zero-downtime guarantee.

## Simultaneous application Pod deletion

One Frontend, one API and one Worker Pod were deleted together. All three
Deployments recovered to `3/3`, but 20 ingress health checks recorded two
timeouts. The result is retained as a limitation and is not marked as a
zero-failure HA pass in the plan. The API-only drill remains the clean
zero-failure evidence in `production-pod-resilience.md`.
