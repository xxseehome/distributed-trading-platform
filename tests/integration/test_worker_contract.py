from backend.models import OrderRequest, as_event
from backend.worker import execution_for


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
