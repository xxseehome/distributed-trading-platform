"""Runtime adapters for local tests and real Redis/Kafka deployments."""

from __future__ import annotations

import asyncio
import hashlib
import json
import os
import re
from decimal import Decimal
from typing import Any

import psycopg
from aiokafka import AIOKafkaProducer
from redis.asyncio import Redis
from redis.asyncio.sentinel import Sentinel

from backend.models import OrderRequest


class DependencyUnavailable(RuntimeError):
    """A required dependency is unavailable in cluster mode."""


class RiskRejected(RuntimeError):
    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


class IdempotencyConflict(RuntimeError):
    """The same idempotency key was reused with a different request."""


SCHEMA_RE = re.compile(r"^[a-z][a-z0-9_]{0,30}$")


def _postgres_dsn() -> str:
    return os.getenv(
        "POSTGRES_DSN",
        "postgresql://{user}:{password}@{host}:{port}/{database}".format(
            user=os.getenv("POSTGRES_USER", "trading"),
            password=os.getenv("POSTGRES_PASSWORD", ""),
            host=os.getenv("POSTGRES_HOST", "postgres"),
            port=os.getenv("POSTGRES_PORT", "5432"),
            database=os.getenv("POSTGRES_DB", "trading"),
        ),
    )


class Runtime:
    def __init__(self) -> None:
        self.environment = os.getenv("TRADING_ENV", "local")
        self.mode = os.getenv("APP_MODE", "local")
        self.cluster_mode = self.mode == "cluster"
        self.max_quantity = Decimal(os.getenv("MAX_ORDER_QUANTITY", "1000"))
        self.max_notional = Decimal(os.getenv("MAX_ORDER_NOTIONAL", "1000000"))
        self.admin_token = os.getenv("ADMIN_TOKEN", "demo-admin")
        self._orders: dict[str, dict[str, Any]] = {}
        self._idempotency: dict[str, tuple[str, str]] = {}
        self._quotes: dict[str, dict[str, Any]] = {
            "ALPHA": {"price": "100.00", "as_of": "simulated"},
            "BETA": {"price": "50.00", "as_of": "simulated"},
            "GAMMA": {"price": "25.00", "as_of": "simulated"},
        }
        self._kill_switch = False
        self._lock = asyncio.Lock()
        self.redis: Redis | None = None
        self.sentinel: Sentinel | None = None
        self.producer: AIOKafkaProducer | None = None
        self._redis_ready = False
        self._kafka_ready = False
        self._postgres_schema = os.getenv("TRADING_SCHEMA", "trading")

    async def start(self) -> None:
        if not self.cluster_mode:
            self._redis_ready = True
            self._kafka_ready = True
            return
        await self._start_redis()
        await self._start_kafka()

    async def close(self) -> None:
        if self.producer is not None:
            await self.producer.stop()
        if self.redis is not None:
            await self.redis.aclose()

    async def _start_redis(self) -> None:
        try:
            sentinel_host = os.getenv("REDIS_SENTINEL_SERVICE")
            if sentinel_host:
                self.sentinel = Sentinel(
                    [(sentinel_host, int(os.getenv("REDIS_SENTINEL_PORT", "26379")))],
                    socket_timeout=1,
                    decode_responses=True,
                )
                self.redis = self.sentinel.master_for(
                    os.getenv("REDIS_MASTER_NAME", "mymaster"), decode_responses=True
                )
            else:
                self.redis = Redis.from_url(
                    os.getenv("REDIS_URL", "redis://redis:6379/0"), decode_responses=True
                )
            await self.redis.ping()
            self._redis_ready = True
        except Exception:
            self._redis_ready = False

    async def _start_kafka(self) -> None:
        try:
            self.producer = AIOKafkaProducer(
                bootstrap_servers=os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092"),
                enable_idempotence=True,
                acks="all",
                request_timeout_ms=3000,
            )
            await self.producer.start()
            self._kafka_ready = True
        except Exception:
            self._kafka_ready = False

    async def readiness(self) -> dict[str, Any]:
        if not self.cluster_mode:
            return {
                "status": "ready",
                "ready": True,
                "environment": self.environment,
                "dependencies": {"redis": "simulated", "kafka": "simulated"},
            }
        redis_ready = self._redis_ready and await self._ping_redis()
        kafka_ready = self._kafka_ready and self.producer is not None
        ready = redis_ready and kafka_ready
        return {
            "status": "ready" if ready else "degraded",
            "ready": ready,
            "environment": self.environment,
            "dependencies": {
                "redis": "ready" if redis_ready else "unavailable",
                "kafka": "ready" if kafka_ready else "unavailable",
                "postgresql": "async_projection_only",
            },
        }

    async def _ping_redis(self) -> bool:
        if self.redis is None:
            return False
        try:
            return bool(await self.redis.ping())
        except Exception:
            return False

    def valid_admin_token(self, supplied: str | None) -> bool:
        return supplied is not None and supplied == self.admin_token

    async def kill_switch_enabled(self) -> bool:
        if not self.cluster_mode or self.redis is None:
            return self._kill_switch
        try:
            return (await self.redis.get("risk:kill-switch")) == "1"
        except Exception as exc:
            raise DependencyUnavailable("Redis is unavailable") from exc

    async def set_kill_switch(self, enabled: bool, reason: str) -> dict[str, Any]:
        if self.cluster_mode:
            if self.redis is None or not self._redis_ready:
                raise DependencyUnavailable("Redis is unavailable")
            try:
                await self.redis.set("risk:kill-switch", "1" if enabled else "0")
            except Exception as exc:
                raise DependencyUnavailable("Redis is unavailable") from exc
        self._kill_switch = enabled
        return {"enabled": enabled, "reason": reason}

    async def check_risk(self, request: OrderRequest) -> None:
        if request.quantity > self.max_quantity:
            raise RiskRejected("max_order_quantity_exceeded")
        if request.quantity * request.limit_price > self.max_notional:
            raise RiskRejected("max_order_notional_exceeded")

    @staticmethod
    def _fingerprint(request: OrderRequest) -> str:
        canonical = request.model_dump_json()
        return hashlib.sha256(canonical.encode()).hexdigest()

    async def lookup_idempotency(self, key: str, request: OrderRequest) -> dict[str, Any] | None:
        fingerprint = self._fingerprint(request)
        if not self.cluster_mode or self.redis is None:
            existing = self._idempotency.get(key)
            if existing is None:
                return None
            if existing[0] != fingerprint:
                raise IdempotencyConflict("idempotency key reused with different request")
            return self._orders.get(existing[1])
        try:
            raw = await self.redis.get(f"idem:{key}")
            if raw is None:
                return None
            value = json.loads(raw)
            if value["fingerprint"] != fingerprint:
                raise IdempotencyConflict("idempotency key reused with different request")
            return await self.get_order(value["order_id"])
        except IdempotencyConflict:
            raise
        except Exception as exc:
            raise DependencyUnavailable("Redis is unavailable") from exc

    async def store_order(self, key: str, request: OrderRequest, order: dict[str, Any]) -> None:
        fingerprint = self._fingerprint(request)
        if not self.cluster_mode or self.redis is None:
            async with self._lock:
                existing = self._idempotency.get(key)
                if existing is not None and existing[0] != fingerprint:
                    raise IdempotencyConflict("idempotency key reused with different request")
                self._idempotency[key] = (fingerprint, order["order_id"])
                self._orders[order["order_id"]] = order
            return
        try:
            await self.redis.set(f"order:{order['order_id']}", json.dumps(order), ex=86400)
            await self.redis.set(
                f"idem:{key}",
                json.dumps({"fingerprint": fingerprint, "order_id": order["order_id"]}),
                ex=86400,
            )
        except Exception as exc:
            raise DependencyUnavailable("Redis is unavailable") from exc

    async def get_order(self, order_id: str) -> dict[str, Any] | None:
        if not self.cluster_mode:
            return self._orders.get(order_id)
        redis_error: Exception | None = None
        if self.redis is not None:
            try:
                raw = await self.redis.get(f"order:{order_id}")
                if raw:
                    return json.loads(raw)
            except Exception as exc:
                redis_error = exc
        else:
            redis_error = DependencyUnavailable("Redis is unavailable")

        try:
            order = await asyncio.to_thread(self._query_postgres_order, order_id)
        except Exception as exc:
            message = "PostgreSQL projection is unavailable"
            if redis_error is not None:
                message = "Redis and PostgreSQL projections are unavailable"
            raise DependencyUnavailable(message) from exc
        return order

    def _query_postgres_order(self, order_id: str) -> dict[str, Any] | None:
        schema = self._postgres_schema
        if not SCHEMA_RE.fullmatch(schema):
            raise ValueError("invalid TRADING_SCHEMA")
        with psycopg.connect(_postgres_dsn(), connect_timeout=3) as connection:
            row = connection.execute(
                f'''SELECT order_id, client_order_id, account_id, symbol, side,
                           quantity, limit_price, status, accepted_at, updated_at, trace_id
                    FROM "{schema}".orders WHERE order_id = %s''',
                (order_id,),
            ).fetchone()
        if row is None:
            return None
        (
            order_id,
            client_order_id,
            account_id,
            symbol,
            side,
            quantity,
            limit_price,
            status,
            accepted_at,
            updated_at,
            trace_id,
        ) = row
        return {
            "order_id": order_id,
            "client_order_id": client_order_id,
            "account_id": account_id,
            "symbol": symbol,
            "side": side,
            "quantity": str(quantity),
            "limit_price": str(limit_price),
            "status": status,
            "occurred_at": accepted_at.isoformat(),
            "updated_at": updated_at.isoformat(),
            "trace_id": trace_id,
        }

    async def publish(self, topic: str, event: dict[str, Any], *, key: str) -> None:
        if not self.cluster_mode:
            return
        if self.producer is None or not self._kafka_ready:
            raise DependencyUnavailable("Kafka is unavailable")
        topic = f"{self.environment}.{topic}"
        try:
            await self.producer.send_and_wait(topic, json.dumps(event).encode(), key=key.encode())
        except Exception as exc:
            raise DependencyUnavailable("Kafka is unavailable") from exc

    async def market_data(self, symbol: str) -> dict[str, Any]:
        if self.cluster_mode and self.redis is not None:
            try:
                raw = await self.redis.get(f"market:{symbol}")
                if raw:
                    return json.loads(raw)
            except Exception as exc:
                raise DependencyUnavailable("Redis is unavailable") from exc
        return self._quotes[symbol]

    async def risk_status(self, account_id: str) -> dict[str, Any]:
        return {
            "account_id": account_id,
            "kill_switch": await self.kill_switch_enabled(),
            "limits": {
                "max_order_quantity": str(self.max_quantity),
                "max_order_notional": str(self.max_notional),
            },
        }

    async def positions(self, account_id: str) -> list[dict[str, Any]]:
        # PostgreSQL is deliberately an asynchronous projection. The worker owns
        # the connection and the API remains available when it is unavailable.
        if self.cluster_mode:
            try:
                return await asyncio.to_thread(self._query_postgres_positions, account_id)
            except Exception as exc:
                raise DependencyUnavailable("PostgreSQL projection is unavailable") from exc
        return []

    def _query_postgres_positions(self, account_id: str) -> list[dict[str, Any]]:
        schema = self._postgres_schema
        if not SCHEMA_RE.fullmatch(schema):
            raise ValueError("invalid TRADING_SCHEMA")
        with psycopg.connect(_postgres_dsn(), connect_timeout=3) as connection:
            rows = connection.execute(
                f'''SELECT symbol, net_quantity, updated_at
                    FROM "{schema}".positions WHERE account_id = %s
                    ORDER BY symbol''',
                (account_id,),
            ).fetchall()
        return [
            {
                "symbol": symbol,
                "net_quantity": str(net_quantity),
                "updated_at": updated_at.isoformat(),
            }
            for symbol, net_quantity, updated_at in rows
        ]
