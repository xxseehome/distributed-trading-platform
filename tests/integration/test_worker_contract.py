from datetime import UTC, datetime
import os
from uuid import uuid4

import psycopg
import pytest

from backend.models import OrderRequest, as_event
from backend.worker import execution_for, project_event


pytestmark = pytest.mark.skipif(
    os.getenv("CI_SERVICE_TESTS") != "1",
    reason="projection tests require the PostgreSQL service container",
)


def test_acceptance_to_execution_contract():
    request = OrderRequest(
        account_id="integration",
        client_order_id="client-1",
        symbol="ALPHA",
        side="BUY",
        quantity="3",
        limit_price="100.00",
    )
    accepted = as_event(
        "OrderAcceptedV1",
        {
            "order_id": "order-1",
            "client_order_id": request.client_order_id,
            "account_id": request.account_id,
            "symbol": request.symbol,
            "side": request.side,
            "quantity": str(request.quantity),
            "limit_price": str(request.limit_price),
        },
        trace_id="trace-1",
    )
    execution = execution_for(accepted)
    assert execution["event_type"] == "ExecutionCreatedV1"
    assert execution["order_id"] == accepted["order_id"]
    assert execution["filled_quantity"] == accepted["quantity"]


def test_projection_deduplicates_events_and_updates_position():
    event_suffix = uuid4().hex
    order_id = f"order-{event_suffix}"
    event = {
        "event_id": f"event-{event_suffix}",
        "event_type": "OrderAcceptedV1",
        "order_id": order_id,
        "client_order_id": f"client-{event_suffix}",
        "account_id": f"account-{event_suffix}",
        "symbol": "ALPHA",
        "side": "BUY",
        "quantity": "3",
        "limit_price": "100.00",
        "occurred_at": datetime.now(UTC).isoformat(),
        "trace_id": f"trace-{event_suffix}",
    }
    execution = {
        **execution_for(event),
        "event_id": f"execution-event-{event_suffix}",
        "occurred_at": datetime.now(UTC).isoformat(),
    }
    dsn = os.environ["POSTGRES_DSN"]

    try:
        with psycopg.connect(dsn) as connection:
            assert project_event(connection, event, "trading") is True
            assert project_event(connection, event, "trading") is False
            assert project_event(connection, execution, "trading") is True
            assert project_event(connection, execution, "trading") is False

            order = connection.execute(
                "SELECT status FROM trading.orders WHERE order_id = %s", (order_id,)
            ).fetchone()
            position = connection.execute(
                """
                SELECT net_quantity
                FROM trading.positions
                WHERE account_id = %s AND symbol = 'ALPHA'
                """,
                (event["account_id"],),
            ).fetchone()
            processed = connection.execute(
                "SELECT count(*) FROM trading.processed_events WHERE event_id IN (%s, %s)",
                (event["event_id"], execution["event_id"]),
            ).fetchone()
            assert order == ("executed",)
            assert str(position[0]) == "3.00000000"
            assert processed == (2,)
    finally:
        with psycopg.connect(dsn) as connection:
            connection.execute(
                "DELETE FROM trading.positions WHERE account_id = %s", (event["account_id"],)
            )
            connection.execute(
                "DELETE FROM trading.executions WHERE order_id = %s", (order_id,)
            )
            connection.execute(
                "DELETE FROM trading.orders WHERE order_id = %s", (order_id,)
            )
            connection.execute(
                "DELETE FROM trading.processed_events WHERE event_id IN (%s, %s)",
                (event["event_id"], execution["event_id"]),
            )
