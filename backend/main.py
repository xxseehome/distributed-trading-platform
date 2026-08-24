"""Trading API for the distributed-system operations lab.

The HTTP service keeps the order-acceptance path deliberately small: Redis is
used for hot state and Kafka is the durable boundary. PostgreSQL is written by
the asynchronous worker and is intentionally not part of ``/readyz``.
"""

from __future__ import annotations

import json
import logging
import os
import re
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from time import perf_counter
from typing import Any
from uuid import uuid4

from fastapi import FastAPI, Header, HTTPException, Request, status
from fastapi.responses import Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

from backend.models import (
    SUPPORTED_SYMBOLS,
    KillSwitchRequest,
    OrderRequest,
    as_event,
)
from backend.runtime import (
    DependencyUnavailable,
    IdempotencyConflict,
    RiskRejected,
    Runtime,
)

runtime = Runtime()
ORDER_ACCEPTED = Counter(
    "trading_orders_accepted_total", "Accepted orders", ["environment", "symbol"]
)
ORDER_REJECTED = Counter(
    "trading_orders_rejected_total", "Rejected orders", ["environment", "reason"]
)
ORDER_LATENCY = Histogram(
    "trading_order_acceptance_seconds", "Order acceptance latency", ["environment"]
)
BUILD_INFO = Gauge(
    "trading_build_info",
    "Build metadata for the running application",
    ["environment", "commit_sha", "image_digest"],
)
LOG = logging.getLogger("trading-api")
TRACEPARENT_RE = re.compile(r"^00-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})$")


def _trace_id(request: Request) -> str:
    """Return the W3C trace id, accepting the legacy demo header as fallback."""

    candidate = request.headers.get("traceparent", "").lower()
    match = TRACEPARENT_RE.fullmatch(candidate)
    if match and match.group(1) != "0" * 32 and match.group(2) != "0" * 16:
        return match.group(1)
    legacy = request.headers.get("X-Trace-Id", "").lower()
    if re.fullmatch(r"[0-9a-f]{32}", legacy):
        return legacy
    return uuid4().hex


@asynccontextmanager
async def lifespan(_: FastAPI):
    await runtime.start()
    yield
    await runtime.close()


app = FastAPI(title="Low-Latency Trading Operations Lab", version="1.0.0", lifespan=lifespan)


@app.on_event("startup")
async def publish_build_info() -> None:
    BUILD_INFO.labels(
        runtime.environment,
        os.getenv("COMMIT_SHA", "unknown"),
        os.getenv("IMAGE_DIGEST", "unknown"),
    ).set(1)


@app.middleware("http")
async def trace_and_log(request: Request, call_next):
    trace_id = _trace_id(request)
    span_id = uuid4().hex[:16]
    request.state.trace_id = trace_id
    started = perf_counter()
    try:
        response = await call_next(request)
    except Exception:
        LOG.exception(
            json.dumps(
                {
                    "event": "http_request_failed",
                    "environment": runtime.environment,
                    "commit_sha": os.getenv("COMMIT_SHA", "unknown"),
                    "image_digest": os.getenv("IMAGE_DIGEST", "unknown"),
                    "trace_id": trace_id,
                    "method": request.method,
                    "path": request.url.path,
                },
                separators=(",", ":"),
            )
        )
        raise
    response.headers["traceparent"] = f"00-{trace_id}-{span_id}-01"
    response.headers["x-trace-id"] = trace_id
    LOG.info(
        json.dumps(
            {
                "event": "http_request",
                "environment": runtime.environment,
                "commit_sha": os.getenv("COMMIT_SHA", "unknown"),
                "image_digest": os.getenv("IMAGE_DIGEST", "unknown"),
                "trace_id": trace_id,
                "method": request.method,
                "path": request.url.path,
                "status": response.status_code,
                "duration_ms": round((perf_counter() - started) * 1000, 3),
            },
            separators=(",", ":"),
        )
    )
    return response


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok", "service": "trading-api"}


@app.get("/health")
async def health_legacy() -> dict[str, str]:
    """Keep the existing demonstration probe while the UI migrates."""

    return {"status": "healthy", "service": "trading-api"}


@app.get("/readyz")
async def readyz() -> dict[str, Any]:
    dependencies = await runtime.readiness()
    if not dependencies["ready"]:
        raise HTTPException(status_code=503, detail=dependencies)
    return dependencies


@app.get("/metrics")
async def metrics() -> Response:
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/api/market-data/{symbol}")
async def market_data(symbol: str) -> dict[str, Any]:
    normalized = symbol.upper()
    if normalized not in SUPPORTED_SYMBOLS:
        raise HTTPException(status_code=404, detail="unsupported symbol")
    quote = await runtime.market_data(normalized)
    return {"symbol": normalized, **quote}


@app.post("/api/orders", status_code=status.HTTP_202_ACCEPTED)
async def create_order(
    request: OrderRequest,
    http_request: Request,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
) -> dict[str, Any]:
    if not idempotency_key:
        raise HTTPException(status_code=400, detail="Idempotency-Key is required")
    if await runtime.kill_switch_enabled():
        ORDER_REJECTED.labels(runtime.environment, "kill_switch").inc()
        raise HTTPException(status_code=503, detail="trading kill switch is enabled")

    started = perf_counter()
    try:
        await runtime.check_risk(request)
        existing = await runtime.lookup_idempotency(idempotency_key, request)
        if existing is not None:
            return existing
        order_id = f"order-{uuid4().hex[:12]}"
        trace_id = getattr(http_request.state, "trace_id", uuid4().hex)
        order = {
            "order_id": order_id,
            "client_order_id": request.client_order_id,
            "account_id": request.account_id,
            "symbol": request.symbol,
            "side": request.side,
            "quantity": str(request.quantity),
            "limit_price": str(request.limit_price),
            "status": "accepted",
            "occurred_at": datetime.now(UTC).isoformat(),
            "trace_id": trace_id,
        }
        event = as_event("OrderAcceptedV1", order, trace_id=trace_id)
        await runtime.publish("orders.accepted.v1", event, key=order_id)
        await runtime.store_order(idempotency_key, request, order)
        ORDER_ACCEPTED.labels(runtime.environment, request.symbol).inc()
        return {**order, "event_type": "OrderAcceptedV1", "schema_version": 1}
    except RiskRejected as exc:
        ORDER_REJECTED.labels(runtime.environment, exc.reason).inc()
        raise HTTPException(status_code=422, detail=exc.reason) from exc
    except IdempotencyConflict as exc:
        ORDER_REJECTED.labels(runtime.environment, "idempotency_conflict").inc()
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except DependencyUnavailable as exc:
        ORDER_REJECTED.labels(runtime.environment, "dependency_unavailable").inc()
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    finally:
        ORDER_LATENCY.labels(runtime.environment).observe(perf_counter() - started)


@app.get("/api/orders/{order_id}")
async def get_order(order_id: str) -> dict[str, Any]:
    try:
        order = await runtime.get_order(order_id)
    except DependencyUnavailable as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    if order is None:
        raise HTTPException(status_code=404, detail="order not found")
    return order


@app.get("/api/positions/{account_id}")
async def get_positions(account_id: str) -> dict[str, Any]:
    try:
        return {"account_id": account_id, "positions": await runtime.positions(account_id)}
    except DependencyUnavailable as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.get("/api/risk/status/{account_id}")
async def risk_status(account_id: str) -> dict[str, Any]:
    return await runtime.risk_status(account_id)


@app.post("/api/admin/kill-switch")
async def kill_switch(
    request: KillSwitchRequest,
    admin_token: str | None = Header(default=None, alias="X-Admin-Token"),
) -> dict[str, Any]:
    if not runtime.valid_admin_token(admin_token):
        raise HTTPException(status_code=403, detail="invalid admin token")
    return await runtime.set_kill_switch(request.enabled, request.reason)
