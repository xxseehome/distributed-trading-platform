# Local production smoke evidence

Collected on 2026-08-23 after the local `trading-production` recovery.
This is a Docker Desktop/k3d experiment and does not represent three physical
failure domains.

## Control plane and workloads

```text
k3d-trading-production-server-0  Ready  172.18.0.2  zone=local-a
k3d-trading-production-server-1  Ready  172.18.0.4  zone=local-b
k3d-trading-production-server-2  Ready  172.18.0.3  zone=local-c

trading-api       3/3 Ready
trading-worker    3/3 Ready
frontend          3/3 Ready
redis             3/3 Ready
redis-sentinel    3/3 Ready
kafka             3/3 Ready
postgres          1/1 Ready
```

The API and worker use the same local image ID:

```text
sha256:6912690ba7fb5e39ca380b9a12fcffa6ac6ca05666b99c507030934d7d1cf15d
```

The frontend image ID is:

```text
sha256:71e7ab285cb7a37e8472873102214c43ee756c438feefded9e6eaa50958c656d
```

## HTTP checks

The Traefik entrypoint is exposed at `http://127.0.0.1:8080` with host
`bookstore.example.invalid`.

```text
GET /                         200  frontend HTML
GET /healthz                  200  {"status":"ok","service":"trading-api"}
GET /api/market-data/ALPHA    200  {"symbol":"ALPHA","price":"100.00","as_of":"simulated"}
```

Through a local API port-forward:

```text
GET /healthz                  200
GET /readyz                   200  redis=ready, kafka=ready
GET /metrics                  200
GET /api/market-data/ALPHA    200
POST /api/orders              202  OrderAcceptedV1
```

The synthetic order with client ID `plan-smoke-1` was projected once into
`production.trading.orders` by the worker (`count=1`). It used no real account,
market feed, or cloud credential.

## Recovery note

The third server briefly became `NotReady` after its Docker IP changed and the
embedded-etcd peer record retained the old address. The member peer URL was
corrected in the local etcd cluster only; no data volume or cloud resource was
deleted. All three servers and workloads are Ready again. The server-stop
limitation is recorded separately in `production-server-failover.md`.
