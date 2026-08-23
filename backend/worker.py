"""Kafka consumer and PostgreSQL projection worker.

The worker is intentionally the only component that writes PostgreSQL. It
commits Kafka offsets after the projection transaction succeeds, giving the
demo an observable at-least-once stream with exactly-once database effects.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

import psycopg
from aiokafka import AIOKafkaConsumer, AIOKafkaProducer

LOG = logging.getLogger("trading-worker")
SCHEMA_RE = re.compile(r"^[a-z][a-z0-9_]{0,30}$")
worker_ready = False


def postgres_dsn() -> str:
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


def schema_name() -> str:
    schema = os.getenv("TRADING_SCHEMA", "trading")
    if not SCHEMA_RE.fullmatch(schema):
        raise ValueError("TRADING_SCHEMA must be a simple lowercase identifier")
    return schema


def ensure_schema(conn: psycopg.Connection[Any], schema: str) -> None:
    if not SCHEMA_RE.fullmatch(schema):
        raise ValueError("invalid schema")
    conn.execute(f'CREATE SCHEMA IF NOT EXISTS "{schema}"')
    conn.execute(
        f'''
        CREATE TABLE IF NOT EXISTS "{schema}".orders (
            order_id text PRIMARY KEY,
            client_order_id text NOT NULL,
            account_id text NOT NULL,
            symbol text NOT NULL,
            side text NOT NULL,
            quantity numeric(18,8) NOT NULL,
            limit_price numeric(18,8) NOT NULL,
            status text NOT NULL,
            accepted_at timestamptz NOT NULL,
            updated_at timestamptz NOT NULL,
            trace_id text NOT NULL
        );
        CREATE TABLE IF NOT EXISTS "{schema}".executions (
            execution_id text PRIMARY KEY,
            order_id text NOT NULL REFERENCES "{schema}".orders(order_id),
            account_id text NOT NULL,
            symbol text NOT NULL,
            filled_quantity numeric(18,8) NOT NULL,
            execution_price numeric(18,8) NOT NULL,
            executed_at timestamptz NOT NULL,
            trace_id text NOT NULL
        );
        CREATE TABLE IF NOT EXISTS "{schema}".positions (
            account_id text NOT NULL,
            symbol text NOT NULL,
            net_quantity numeric(18,8) NOT NULL DEFAULT 0,
            updated_at timestamptz NOT NULL,
            PRIMARY KEY (account_id, symbol)
        );
        CREATE TABLE IF NOT EXISTS "{schema}".processed_events (
            event_id text PRIMARY KEY,
            event_type text NOT NULL,
            processed_at timestamptz NOT NULL
        );
        '''
    )
    conn.commit()


def project_event(conn: psycopg.Connection[Any], event: dict[str, Any], schema: str) -> bool:
    """Project one event and return False when it was already processed."""

    if not SCHEMA_RE.fullmatch(schema):
        raise ValueError("invalid schema")
    event_id = event["event_id"]
    inserted = conn.execute(
        f'''INSERT INTO "{schema}".processed_events(event_id, event_type, processed_at)
            VALUES (%s, %s, %s) ON CONFLICT (event_id) DO NOTHING''',
        (event_id, event["event_type"], datetime.now(UTC)),
    ).rowcount
    if inserted == 0:
        conn.rollback()
        return False

    event_type = event["event_type"]
    now = datetime.now(UTC)
    if event_type == "OrderAcceptedV1":
        conn.execute(
            f'''
            INSERT INTO "{schema}".orders
              (order_id, client_order_id, account_id, symbol, side, quantity,
               limit_price, status, accepted_at, updated_at, trace_id)
            VALUES (%s, %s, %s, %s, %s, %s, %s, 'accepted', %s, %s, %s)
            ON CONFLICT (order_id) DO UPDATE SET updated_at = EXCLUDED.updated_at
            ''',
            (
                event["order_id"],
                event["client_order_id"],
                event["account_id"],
                event["symbol"],
                event["side"],
                Decimal(event["quantity"]),
                Decimal(event["limit_price"]),
                event["occurred_at"],
                now,
                event["trace_id"],
            ),
        )
    elif event_type == "ExecutionCreatedV1":
        conn.execute(
            f'''
            INSERT INTO "{schema}".executions
              (execution_id, order_id, account_id, symbol, filled_quantity,
               execution_price, executed_at, trace_id)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (execution_id) DO NOTHING
            ''',
            (
                event["execution_id"],
                event["order_id"],
                event["account_id"],
                event["symbol"],
                Decimal(event["filled_quantity"]),
                Decimal(event["execution_price"]),
                event["occurred_at"],
                event["trace_id"],
            ),
        )
        conn.execute(
            f'''UPDATE "{schema}".orders SET status='executed', updated_at=%s
                WHERE order_id=%s''',
            (now, event["order_id"]),
        )
        sign = Decimal("1") if event.get("side", "BUY") == "BUY" else Decimal("-1")
        conn.execute(
            f'''
            INSERT INTO "{schema}".positions(account_id, symbol, net_quantity, updated_at)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (account_id, symbol) DO UPDATE
              SET net_quantity = "{schema}".positions.net_quantity + EXCLUDED.net_quantity,
                  updated_at = EXCLUDED.updated_at
            ''',
            (
                event["account_id"],
                event["symbol"],
                sign * Decimal(event["filled_quantity"]),
                now,
            ),
        )
    conn.commit()
    return True


def execution_for(event: dict[str, Any]) -> dict[str, Any]:
    return {
        "event_id": f"exec-{event['event_id']}",
        "event_type": "ExecutionCreatedV1",
        "schema_version": 1,
        "execution_id": f"execution-{event['order_id']}",
        "order_id": event["order_id"],
        "account_id": event["account_id"],
        "symbol": event["symbol"],
        "side": event["side"],
        "filled_quantity": event["quantity"],
        "execution_price": event["limit_price"],
        "occurred_at": datetime.now(UTC).isoformat(),
        "trace_id": event["trace_id"],
    }


async def process_message(
    message: Any,
    conn: psycopg.Connection[Any],
    consumer: AIOKafkaConsumer,
    producer: AIOKafkaProducer,
    topic_prefix: str,
    schema: str,
) -> None:
    """Project one Kafka message before committing its offset.

    Keeping the commit as the final operation makes the delivery contract
    explicit and testable: a projection or follow-up execution publish error
    leaves the offset uncommitted so Kafka can redeliver the event.
    """

    event = json.loads(message.value)
    await asyncio.to_thread(project_event, conn, event, schema)
    if event["event_type"] == "OrderAcceptedV1":
        execution = execution_for(event)
        await producer.send_and_wait(
            f"{topic_prefix}.executions.v1",
            json.dumps(execution).encode(),
            key=event["order_id"].encode(),
        )
    await consumer.commit()


async def run() -> None:
    global worker_ready
    logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
    bootstrap = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
    environment = os.getenv("TRADING_ENV", "local")
    topic_prefix = os.getenv("KAFKA_TOPIC_PREFIX", environment)
    topics = [f"{topic_prefix}.orders.accepted.v1", f"{topic_prefix}.executions.v1"]
    consumer = AIOKafkaConsumer(
        *topics,
        bootstrap_servers=bootstrap,
        group_id=f"{environment}-projection",
        enable_auto_commit=False,
        auto_offset_reset="earliest",
    )
    producer = AIOKafkaProducer(bootstrap_servers=bootstrap, enable_idempotence=True, acks="all")
    _health_server = await start_health_server(int(os.getenv("WORKER_HEALTH_PORT", "8001")))
    while True:
        try:
            with psycopg.connect(postgres_dsn(), connect_timeout=3) as conn:
                ensure_schema(conn, schema_name())
                await consumer.start()
                await producer.start()
                worker_ready = True
                try:
                    async for message in consumer:
                        await process_message(
                            message,
                            conn,
                            consumer,
                            producer,
                            topic_prefix,
                            schema_name(),
                        )
                finally:
                    worker_ready = False
                    await producer.stop()
                    await consumer.stop()
        except Exception:
            worker_ready = False
            LOG.exception("worker dependency loop failed; retrying without committing offsets")
            await asyncio.sleep(5)


async def start_health_server(port: int) -> asyncio.AbstractServer:
    async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        global worker_ready
        await reader.read(1024)
        code = 200 if worker_ready else 503
        phrase = "OK" if worker_ready else "Service Unavailable"
        body = ("ready" if worker_ready else "degraded").encode()
        writer.write(
            f"HTTP/1.1 {code} {phrase}\\r\\nContent-Length: {len(body)}\\r\\n"
            "Content-Type: text/plain\\r\\nConnection: close\\r\\n\\r\\n".encode()
            + body
        )
        await writer.drain()
        writer.close()
        await writer.wait_closed()

    return await asyncio.start_server(handle, "0.0.0.0", port)


if __name__ == "__main__":
    asyncio.run(run())
