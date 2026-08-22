"""Public request and event models for the trading lab."""

from __future__ import annotations

from datetime import UTC, datetime
from decimal import Decimal
from typing import Any, Literal
from uuid import uuid4

from pydantic import BaseModel, Field, field_validator

SUPPORTED_SYMBOLS = {"ALPHA", "BETA", "GAMMA"}


class OrderRequest(BaseModel):
    account_id: str = Field(min_length=1, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    client_order_id: str = Field(min_length=1, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    symbol: str = Field(min_length=1, max_length=16)
    side: Literal["BUY", "SELL"]
    quantity: Decimal = Field(gt=0, le=100_000)
    limit_price: Decimal = Field(gt=0, le=1_000_000_000)

    @field_validator("symbol")
    @classmethod
    def normalize_symbol(cls, value: str) -> str:
        value = value.upper()
        if value not in SUPPORTED_SYMBOLS:
            raise ValueError("unsupported symbol")
        return value


class KillSwitchRequest(BaseModel):
    enabled: bool
    reason: str = Field(min_length=3, max_length=256)


def as_event(event_type: str, payload: dict[str, Any], *, trace_id: str) -> dict[str, Any]:
    return {
        "event_id": str(uuid4()),
        "event_type": event_type,
        "schema_version": 1,
        "occurred_at": datetime.now(UTC).isoformat(),
        "trace_id": trace_id,
        **payload,
    }
