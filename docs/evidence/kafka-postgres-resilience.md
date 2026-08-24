# Kafka and PostgreSQL resilience evidence

Collected during the local execution on 2026-08-23. This is a local k3d
experiment; no cloud resource was changed.

## Kafka resource boundary

The production Kafka StatefulSet rolled all three brokers successfully with:

```text
KAFKA_HEAP_OPTS=-Xms256m -Xmx384m
KAFKA_LOG_RETENTION_HOURS=6
kafka-0/1/2: 1/1 Ready
```

The same heap setting is present in both `k8s/base/kafka.yaml` and
`k8s/base-data/kafka.yaml`.

## PostgreSQL outage and recovery

The single production PostgreSQL StatefulSet was scaled from one replica to
zero and then restored to one. The PVC was retained.

During the outage:

```text
GET /api/orders/order-pg-outage-missing -> 503
{"detail":"PostgreSQL projection is unavailable"}
POST /api/orders (valid BUY order) -> 202
client_order_id=pg-outage-c4d590b6
order_id=order-cbf8e175ff8c
```

After PostgreSQL returned and the Worker restarted its dependency loop, the
uncommitted Kafka event was projected automatically:

```text
trading.orders: pg-outage-c4d590b6 | executed
postgres-0: 1/1 Ready
trading-worker: 3/3 Ready
```

The Worker now creates fresh aiokafka consumer/producer clients for each
dependency attempt, so a database interruption does not reuse a stopped
consumer or lose the uncommitted offset.
