"""Validate the database objects created by the integration migration gate."""

import os

import psycopg


def main() -> None:
    dsn = os.environ["POSTGRES_DSN"]
    with psycopg.connect(dsn) as connection:
        rows = connection.execute(
            """
            SELECT table_schema, table_name
            FROM information_schema.tables
            WHERE table_schema = 'trading'
            ORDER BY table_name
            """
        ).fetchall()
    expected = {
        ("trading", "executions"),
        ("trading", "orders"),
        ("trading", "positions"),
        ("trading", "processed_events"),
    }
    actual = set(rows)
    if actual != expected:
        raise SystemExit(f"schema mismatch: expected {expected!r}, got {actual!r}")
    print(f"validated {len(actual)} trading tables")


if __name__ == "__main__":
    main()
