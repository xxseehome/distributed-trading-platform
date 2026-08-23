import asyncio
import json

import pytest
from fastapi.testclient import TestClient

from backend.main import app, runtime
from backend.models import OrderRequest, as_event
from backend.worker import execution_for, process_message

client = TestClient(app)


def order_body(client_order_id: str = "client-1") -> dict[str, str]:
    return {
        "account_id": "demo-account",
        "client_order_id": client_order_id,
        "symbol": "ALPHA",
        "side": "BUY",
        "quantity": "2",
        "limit_price": "100.00",
    }


def test_health_readiness_and_metrics():
    assert client.get("/healthz").json()["status"] == "ok"
    readiness = client.get("/readyz")
    assert readiness.status_code == 200
    assert readiness.json()["dependencies"]["redis"] == "simulated"
    assert "trading_orders_accepted_total" in client.get("/metrics").text


def test_market_data_is_deterministic():
    response = client.get("/api/market-data/alpha")
    assert response.status_code == 200
    assert response.json() == {"symbol": "ALPHA", "price": "100.00", "as_of": "simulated"}
    assert client.get("/api/market-data/unknown").status_code == 404


def test_order_requires_idempotency_key():
    response = client.post("/api/orders", json=order_body())
    assert response.status_code == 400


def test_order_is_idempotent():
    body = order_body("client-idempotent")
    first = client.post("/api/orders", headers={"Idempotency-Key": "demo-1"}, json=body)
    second = client.post("/api/orders", headers={"Idempotency-Key": "demo-1"}, json=body)
    assert first.status_code == second.status_code == 202
    assert first.json()["order_id"] == second.json()["order_id"]
    assert first.json()["event_type"] == "OrderAcceptedV1"


def test_idempotency_conflict_is_rejected():
    first = client.post(
        "/api/orders", headers={"Idempotency-Key": "conflict-key"}, json=order_body("one")
    )
    assert first.status_code == 202
    second = client.post(
        "/api/orders", headers={"Idempotency-Key": "conflict-key"}, json=order_body("two")
    )
    assert second.status_code == 409


def test_risk_limits_and_kill_switch():
    oversized = order_body("too-large")
    oversized["quantity"] = "1001"
    assert (
        client.post(
            "/api/orders", headers={"Idempotency-Key": "risk-key"}, json=oversized
        ).status_code
        == 422
    )
    assert (
        client.post(
            "/api/admin/kill-switch",
            headers={"X-Admin-Token": "demo-admin"},
            json={"enabled": True, "reason": "maintenance"},
        ).status_code
        == 200
    )
    assert (
        client.post(
            "/api/orders", headers={"Idempotency-Key": "blocked-key"}, json=order_body("blocked")
        ).status_code
        == 503
    )
    assert (
        client.post(
            "/api/admin/kill-switch",
            headers={"X-Admin-Token": "demo-admin"},
            json={"enabled": False, "reason": "maintenance complete"},
        ).status_code
        == 200
    )


def test_order_query_and_positions():
    response = client.post(
        "/api/orders", headers={"Idempotency-Key": "query-key"}, json=order_body("query")
    )
    order_id = response.json()["order_id"]
    assert client.get(f"/api/orders/{order_id}").json()["order_id"] == order_id
    assert client.get("/api/orders/not-found").status_code == 404
    assert client.get("/api/positions/demo-account").json() == {
        "account_id": "demo-account",
        "positions": [],
    }


def test_cluster_order_query_falls_back_to_postgres(monkeypatch):
    monkeypatch.setattr(runtime, "cluster_mode", True)
    monkeypatch.setattr(runtime, "redis", None)
    monkeypatch.setattr(
        runtime,
        "_query_postgres_order",
        lambda order_id: {"order_id": order_id, "status": "executed"},
    )

    response = client.get("/api/orders/history-order")

    assert response.status_code == 200
    assert response.json() == {"order_id": "history-order", "status": "executed"}


def test_cluster_order_query_reports_degraded_when_postgres_is_unavailable(monkeypatch):
    monkeypatch.setattr(runtime, "cluster_mode", True)
    monkeypatch.setattr(runtime, "redis", None)

    def unavailable(_: str):
        raise RuntimeError("database down")

    monkeypatch.setattr(runtime, "_query_postgres_order", unavailable)

    response = client.get("/api/orders/history-order")

    assert response.status_code == 503
    assert "PostgreSQL" in response.json()["detail"]


def test_cluster_positions_read_from_postgres_projection(monkeypatch):
    monkeypatch.setattr(runtime, "cluster_mode", True)
    monkeypatch.setattr(
        runtime,
        "_query_postgres_positions",
        lambda account_id: [{"symbol": "ALPHA", "net_quantity": "2", "account_id": account_id}],
    )

    response = client.get("/api/positions/demo-account")

    assert response.status_code == 200
    assert response.json() == {
        "account_id": "demo-account",
        "positions": [{"symbol": "ALPHA", "net_quantity": "2", "account_id": "demo-account"}],
    }


def test_event_contract_and_execution():
    request = OrderRequest(**order_body("event"))
    event = as_event(
        "OrderAcceptedV1",
        {
            "order_id": "order-event",
            "client_order_id": request.client_order_id,
            "account_id": request.account_id,
            "symbol": request.symbol,
            "side": request.side,
            "quantity": str(request.quantity),
            "limit_price": str(request.limit_price),
        },
        trace_id="trace-event",
    )
    execution = execution_for(event)
    assert event["schema_version"] == execution["schema_version"] == 1
    assert execution["order_id"] == event["order_id"]
    assert execution["trace_id"] == event["trace_id"]


def test_admin_requires_token():
    response = client.post("/api/admin/kill-switch", json={"enabled": True, "reason": "no token"})
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_cluster_readiness_reports_redis_and_kafka_failure(monkeypatch):
    monkeypatch.setattr(runtime, "cluster_mode", True)
    monkeypatch.setattr(runtime, "redis", None)
    monkeypatch.setattr(runtime, "producer", None)
    monkeypatch.setattr(runtime, "_redis_ready", False)
    monkeypatch.setattr(runtime, "_kafka_ready", False)

    readiness = await runtime.readiness()

    assert readiness == {
        "status": "degraded",
        "ready": False,
        "environment": runtime.environment,
        "dependencies": {
            "redis": "unavailable",
            "kafka": "unavailable",
            "postgresql": "async_projection_only",
        },
    }


@pytest.mark.asyncio
async def test_postgres_failure_does_not_block_order_acceptance(monkeypatch):
    monkeypatch.setattr(runtime, "cluster_mode", True)
    monkeypatch.setattr(runtime, "redis", None)
    monkeypatch.setattr(runtime, "_kafka_ready", True)
    monkeypatch.setattr(runtime, "publish", lambda *args, **kwargs: asyncio.sleep(0))
    monkeypatch.setattr(runtime, "store_order", lambda *args, **kwargs: asyncio.sleep(0))

    response = client.post(
        "/api/orders",
        headers={"Idempotency-Key": "postgres-outage-key"},
        json=order_body("postgres-outage"),
    )

    assert response.status_code == 202
    assert response.json()["status"] == "accepted"


class _FakeMessage:
    def __init__(self, event: dict[str, object]):
        self.value = json.dumps(event).encode()


class _FakeConsumer:
    def __init__(self):
        self.commits = 0

    async def commit(self):
        self.commits += 1


class _FakeProducer:
    def __init__(self):
        self.messages: list[tuple[str, bytes, bytes]] = []

    async def send_and_wait(self, topic: str, value: bytes, key: bytes):
        self.messages.append((topic, value, key))


class _FailingProducer(_FakeProducer):
    async def send_and_wait(self, topic: str, value: bytes, key: bytes):
        raise RuntimeError("execution publish unavailable")


@pytest.mark.asyncio
async def test_worker_commits_only_after_projection_and_publish(monkeypatch):
    event = {
        "event_id": "event-worker-contract",
        "event_type": "OrderAcceptedV1",
        "order_id": "order-worker-contract",
        "client_order_id": "client-worker-contract",
        "account_id": "account-worker-contract",
        "symbol": "ALPHA",
        "side": "BUY",
        "quantity": "1",
        "limit_price": "100",
        "occurred_at": "2026-01-01T00:00:00+00:00",
        "trace_id": "trace-worker-contract",
    }
    consumer = _FakeConsumer()
    producer = _FakeProducer()
    monkeypatch.setattr("backend.worker.project_event", lambda *args: True)

    await process_message(_FakeMessage(event), object(), consumer, producer, "test", "trading")

    assert consumer.commits == 1
    assert producer.messages[0][0] == "test.executions.v1"


@pytest.mark.asyncio
async def test_worker_does_not_commit_when_projection_fails(monkeypatch):
    event = {
        "event_id": "event-worker-failure",
        "event_type": "OrderAcceptedV1",
        "order_id": "order-worker-failure",
    }
    consumer = _FakeConsumer()
    producer = _FakeProducer()

    def fail_projection(*args):
        raise RuntimeError("projection unavailable")

    monkeypatch.setattr("backend.worker.project_event", fail_projection)

    with pytest.raises(RuntimeError, match="projection unavailable"):
        await process_message(_FakeMessage(event), object(), consumer, producer, "test", "trading")

    assert consumer.commits == 0


@pytest.mark.asyncio
async def test_worker_does_not_commit_when_execution_publish_fails(monkeypatch):
    event = {
        "event_id": "event-publish-failure",
        "event_type": "OrderAcceptedV1",
        "order_id": "order-publish-failure",
        "client_order_id": "client-publish-failure",
        "account_id": "account-publish-failure",
        "symbol": "ALPHA",
        "side": "BUY",
        "quantity": "1",
        "limit_price": "100",
        "occurred_at": "2026-01-01T00:00:00+00:00",
        "trace_id": "trace-publish-failure",
    }
    consumer = _FakeConsumer()
    monkeypatch.setattr("backend.worker.project_event", lambda *args: True)

    with pytest.raises(RuntimeError, match="execution publish unavailable"):
        await process_message(
            _FakeMessage(event), object(), consumer, _FailingProducer(), "test", "trading"
        )

    assert consumer.commits == 0
