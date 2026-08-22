# Trading System Architecture

This document is the implementation view of
[`Plan-Trading-System.md`](Plan-Trading-System.md). It is intentionally explicit
about the PostgreSQL availability boundary: the order acceptance path is highly
available in Production, while PostgreSQL is a single asynchronous projection
primary in v1.

## Cloud and cluster topology

```mermaid
flowchart TB
    USER["Operator / Interview Demo"]
    GH["GitHub PR + Actions + Environments"]
    RAM["Alibaba RAM OIDC"]
    TF["Terraform"]
    CA["Cloud Assistant / Ansible"]
    OBS["Grafana Cloud Free"]

    USER --> GH --> RAM --> TF
    RAM --> CA

    subgraph HZ["Hangzhou"]
        NP["Non-production K3s<br/>dev/test/perf/staging"]
        PROD["Production K3s<br/>Server 1 / AZ-A<br/>Server 2 / AZ-B<br/>Server 3 / AZ-C"]
        HZDATA["ACR + OSS + Tablestore"]
    end
    subgraph BJ["Beijing"]
        DR["DR K3s<br/>single warm node"]
        BJDATA["ACR + OSS restore data"]
    end

    TF --> NP
    TF --> PROD
    TF --> DR
    CA --> NP
    CA --> PROD
    CA --> DR
    HZDATA --> NP
    HZDATA --> PROD
    HZDATA --> BJDATA --> DR
    NP --> OBS
    PROD --> OBS
    DR --> OBS
```

## Application and data flow

```mermaid
flowchart LR
    CLIENT["Trader UI / Synthetic Check"] --> CLB["CLB :80"] --> TRAEFIK["Traefik"] --> WEB["Nginx"]
    WEB --> API["Trading API ×3"]
    API --> RISK["Redis risk / idempotency / kill switch"]
    API -->|"OrderAcceptedV1 · acks=all"| KAFKA["Kafka KRaft ×3"]
    KAFKA --> WORKER["Worker ×3"]
    WORKER -->|"ExecutionCreatedV1"| KAFKA
    WORKER --> REDIS["Redis live order state"]
    WORKER --> PG["PostgreSQL async projection"]
    WORKER --> OSS["OSS archive / backup"]
    API -. "history only" .-> PG
```

## Delivery and operations

```mermaid
flowchart LR
    PR["PR"] --> TEST["Ruff + pytest + integration"]
    TEST --> SEC["Gitleaks + Trivy + Syft + OPA"]
    SEC --> BUILD["Build once + Cosign"]
    BUILD --> DEV["dev"] --> TESTENV["test"] --> PERF["perf"] --> STAGE["staging approval"] --> PROD["production approval"]
    PROD --> DR["Beijing DR same digest"]
    APP["API + Worker + Redis + Kafka + PostgreSQL"] --> ALLOY["Grafana Alloy"] --> GRAFANA["Grafana Cloud"]
    GRAFANA --> INCIDENT["GitHub Incident + approved remediation"]
```

## Environment and data-plane separation

The four non-production application namespaces (`dev`, `test`, `perf`, and
`staging`) share one low-cost data plane in `nonprod-platform`. Each application
namespace uses its own Kafka topic prefix and PostgreSQL schema; the shared
services do not imply shared order data. Production and DR each keep their data
plane in the cluster namespace. This keeps the three-cluster topology explicit
without creating four additional Kafka, Redis, or PostgreSQL installations.

```mermaid
flowchart LR
    DEV["dev"] --> NPD["nonprod-platform data plane"]
    TEST["test"] --> NPD
    PERF["perf"] --> NPD
    STAGE["staging"] --> NPD
    NPD --> REDIS["Redis/Sentinel"]
    NPD --> KAFKA["Kafka topics by environment"]
    NPD --> PG["PostgreSQL schemas by environment"]
    PROD["production"] --> PDATA["production data plane"]
    DR["production-dr"] --> DRDATA["DR data plane"]
```

The shared non-production data policy only permits the four application
namespaces and the topic-init Job to reach Redis, Sentinel, Kafka, and
PostgreSQL. Production still uses the stricter in-namespace policy. Credentials
are referenced as Kubernetes Secrets and are intentionally absent from Git.

## Availability boundary

| Component | Production target | Failure behavior |
|---|---|---|
| K3s control plane | 3 servers, 3 AZs | etcd keeps quorum after one server loss |
| Trading API | 3 replicas, spread across AZs | orders continue through another replica |
| Worker | 3 replicas, spread across AZs | Kafka consumer group rebalances |
| Kafka | 3 KRaft brokers, RF=3, min ISR=2 | accepted events remain durable |
| Redis | 1 primary, 2 replicas, 3 Sentinel | hot state fails over |
| PostgreSQL | 1 primary, 5 GiB PVC | history/projection degrades; orders continue; backlog drains after recovery |
| DR | Beijing single warm node | restored manually; no HA claim |

## Explicit non-goals

- No real exchange connectivity or FIX network session.
- No nanosecond HFT claim on general-purpose ECS/K3s.
- No Patroni, CloudNativePG, RDS, Longhorn or additional paid managed services.
- No new public ingress beyond the existing CLB demonstration boundary.
