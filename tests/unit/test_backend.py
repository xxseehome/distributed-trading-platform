from fastapi.testclient import TestClient

from backend.main import app, runtime
from backend.models import OrderRequest, as_event
from backend.worker import execution_for

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
        "positions": [
            {"symbol": "ALPHA", "net_quantity": "2", "account_id": "demo-account"}
        ],
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
