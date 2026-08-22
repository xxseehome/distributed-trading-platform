"""Create the trading projection tables."""

from alembic import op

revision = "001_initial"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("CREATE SCHEMA IF NOT EXISTS trading")
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS trading.orders (
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
        CREATE TABLE IF NOT EXISTS trading.executions (
          execution_id text PRIMARY KEY,
          order_id text NOT NULL REFERENCES trading.orders(order_id),
          account_id text NOT NULL,
          symbol text NOT NULL,
          filled_quantity numeric(18,8) NOT NULL,
          execution_price numeric(18,8) NOT NULL,
          executed_at timestamptz NOT NULL,
          trace_id text NOT NULL
        );
        CREATE TABLE IF NOT EXISTS trading.positions (
          account_id text NOT NULL,
          symbol text NOT NULL,
          net_quantity numeric(18,8) NOT NULL DEFAULT 0,
          updated_at timestamptz NOT NULL,
          PRIMARY KEY (account_id, symbol)
        );
        CREATE TABLE IF NOT EXISTS trading.processed_events (
          event_id text PRIMARY KEY,
          event_type text NOT NULL,
          processed_at timestamptz NOT NULL
        );
        """
    )


def downgrade() -> None:
    op.execute("DROP SCHEMA IF EXISTS trading CASCADE")
