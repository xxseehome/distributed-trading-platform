#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$repo_root/.tools/bin:$PATH"
runtime_root="${RUNTIME_ROOT:-$repo_root/.runtime}"
production_kubeconfig="${LOCAL_PRODUCTION_KUBECONFIG:-$runtime_root/kubeconfigs/production}"
backup_dir="${BACKUP_DIR:-$runtime_root/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

test -s "$production_kubeconfig"
mkdir -p "$backup_dir"
export KUBECONFIG="$production_kubeconfig"

postgres_pod="$(kubectl -n production get pods -l app.kubernetes.io/name=postgres \
  --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
kafka_pod="$(kubectl -n production get pods -l app.kubernetes.io/name=kafka \
  --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
test -n "$postgres_pod"
test -n "$kafka_pod"

postgres_backup="$backup_dir/postgres-$timestamp.sql.gz"
kubectl -n production exec "$postgres_pod" -- pg_dump -U trading -d trading \
  | gzip > "$postgres_backup"
chmod 0600 "$postgres_backup"

# Kafka event recovery is intentionally minimal for the local low-resource
# profile: retain topic names and consumer-group offsets, while the immutable
# event stream remains in the broker PVCs. Do not put message payloads in an
# Actions artifact.
kafka_snapshot="$backup_dir/kafka-$timestamp.txt"
{
  echo "captured_at=$timestamp"
  echo "topics:"
  kubectl -n production exec "$kafka_pod" -- \
    /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list
  echo "consumer_offsets:"
  kubectl -n production exec "$kafka_pod" -- \
    /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server kafka:9092 \
    --all-groups --describe 2>&1 || true
} > "$kafka_snapshot"
chmod 0600 "$kafka_snapshot"

echo "PostgreSQL backup: $postgres_backup"
echo "Kafka metadata snapshot: $kafka_snapshot"
