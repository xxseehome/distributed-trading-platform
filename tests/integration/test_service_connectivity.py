"""Smoke-test the CI service containers used by the integration gate."""

from __future__ import annotations

import asyncio
import os
import time

import psycopg
import pytest
import redis
from aiokafka import AIOKafkaConsumer

pytestmark = pytest.mark.skipif(
    os.getenv("CI_SERVICE_TESTS") != "1",
    reason="service containers are enabled only in GitHub Actions",
)


def test_redis_round_trip() -> None:
    client = redis.Redis.from_url(os.environ["REDIS_URL"], decode_responses=True)
    key = "ci:service-smoke"
    client.set(key, "ready", ex=30)
    assert client.get(key) == "ready"


def test_postgres_migration_marker() -> None:
    with psycopg.connect(os.environ["POSTGRES_DSN"]) as connection:
        revision = connection.execute(
            "SELECT version_num FROM alembic_version"
        ).fetchone()
    assert revision == ("001_initial",)


@pytest.mark.asyncio
async def test_kafka_metadata() -> None:
    deadline = time.monotonic() + 45
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        consumer = AIOKafkaConsumer(
            bootstrap_servers=os.environ["KAFKA_BOOTSTRAP_SERVERS"],
            request_timeout_ms=5000,
        )
        started = False
        try:
            await asyncio.wait_for(consumer.start(), timeout=10)
            started = True
            topics = await asyncio.wait_for(consumer.topics(), timeout=10)
            assert isinstance(topics, set)
            return
        except Exception as error:  # pragma: no cover - depends on service startup
            last_error = error
            await asyncio.sleep(2)
        finally:
            if started:
                await consumer.stop()
    raise AssertionError(f"Kafka did not become ready: {last_error!r}")
