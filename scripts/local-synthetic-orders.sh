#!/usr/bin/env bash
set -euo pipefail

# Run a bounded, low-rate synthetic order stream against the local demo entrypoint.
# This is intentionally finite and uses no real account or market connection.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
duration_seconds="${1:-60}"
interval_seconds="${INTERVAL_SECONDS:-5}"
base_url="${BASE_URL:-http://127.0.0.1:8080}"
route_host="${ROUTE_HOST:-bookstore.example.invalid}"

[[ "$duration_seconds" =~ ^[0-9]+$ ]] && (( duration_seconds > 0 ))
[[ "$interval_seconds" =~ ^[0-9]+$ ]] && (( interval_seconds > 0 ))

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/synthetic-orders.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
deadline=$(( $(date +%s) + duration_seconds ))
accepted=0
failed=0
attempts=0

while (( $(date +%s) < deadline )); do
  attempts=$((attempts + 1))
  client_order_id="synthetic-$(date -u +%Y%m%dT%H%M%SZ)-${attempts}"
  body="{\"account_id\":\"synthetic-account\",\"client_order_id\":\"${client_order_id}\",\"symbol\":\"ALPHA\",\"side\":\"BUY\",\"quantity\":\"1\",\"limit_price\":\"100.00\"}"
  status="$(curl --fail --silent --show-error --max-time 5 \
    -o "$tmp_dir/response" -w '%{http_code}' \
    -H "Host: $route_host" \
    -H 'Content-Type: application/json' \
    -H "Idempotency-Key: $client_order_id" \
    -d "$body" "$base_url/api/orders" || true)"
  if [[ "$status" == 202 ]]; then
    accepted=$((accepted + 1))
  else
    failed=$((failed + 1))
    printf 'failed_order=%s status=%s\n' "$client_order_id" "${status:-curl-error}"
  fi
  sleep "$interval_seconds"
done

finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'started_at=%s\nfinished_at=%s\nduration_seconds=%s\ninterval_seconds=%s\nattempts=%s\naccepted=%s\nfailed=%s\n' \
  "$started_at" "$finished_at" "$duration_seconds" "$interval_seconds" "$attempts" "$accepted" "$failed"
(( failed == 0 ))
