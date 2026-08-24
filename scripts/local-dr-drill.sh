#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$repo_root/.tools/bin:$PATH"
release_file="${1:?release.json path is required}"
backup_file="${2:?backup file path is required}"
production_kubeconfig="${LOCAL_PRODUCTION_KUBECONFIG:-$repo_root/.runtime/kubeconfigs/production}"
test -s "$release_file"
test -s "$backup_file"
test -s "$production_kubeconfig"

dr_kubeconfig="${RUNNER_TEMP:-/tmp}/vcluster-dr.kubeconfig"
vcluster_pid=""
api_port_forward_pid=""
dr_active=false
cleanup_vcluster() {
  set +e
  if [[ "$dr_active" == true ]]; then
    for workload in trading-api trading-worker frontend; do
      kubectl -n production-dr scale "deploy/$workload" --replicas=0 >/dev/null
    done
    for workload in redis kafka postgres; do
      kubectl -n production-dr scale "statefulset/$workload" --replicas=0 >/dev/null
    done
    kubectl -n production-dr scale deployment/redis-sentinel --replicas=0 >/dev/null
  fi
  if [[ -n "$api_port_forward_pid" ]]; then
    kill "$api_port_forward_pid" 2>/dev/null || true
    wait "$api_port_forward_pid" 2>/dev/null || true
  fi
  if [[ -n "$vcluster_pid" ]]; then
    kill "$vcluster_pid" 2>/dev/null || true
    wait "$vcluster_pid" 2>/dev/null || true
  fi
}
trap cleanup_vcluster EXIT

: > "$dr_kubeconfig"
vcluster connect dr --namespace vcluster-dr --insecure \
  --print --background-proxy=false > "$dr_kubeconfig" \
  2>"$dr_kubeconfig.log" &
vcluster_pid=$!
for _ in {1..60}; do
  if grep -q '^current-context:' "$dr_kubeconfig"; then
    # vcluster appends port-forward notices to stdout after the YAML.
    sed '/^Forwarding from/,$d' "$dr_kubeconfig" > "$dr_kubeconfig.cleaned"
    mv "$dr_kubeconfig.cleaned" "$dr_kubeconfig"
    chmod 0600 "$dr_kubeconfig"
    break
  fi
  sleep 1
done
if ! grep -q '^current-context:' "$dr_kubeconfig"; then
  echo "Timed out waiting for vCluster kubeconfig: dr" >&2
  cat "$dr_kubeconfig.log" >&2 || true
  exit 1
fi
for _ in {1..60}; do
  if KUBECONFIG="$dr_kubeconfig" kubectl get namespace >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
if ! KUBECONFIG="$dr_kubeconfig" kubectl get namespace >/dev/null 2>&1; then
  echo "Timed out waiting for vCluster API: dr" >&2
  cat "$dr_kubeconfig.log" >&2 || true
  exit 1
fi
export KUBECONFIG="$dr_kubeconfig"

api_image="$(jq -r .api_image "$release_file")"
frontend_image="$(jq -r .frontend_image "$release_file")"
commit_sha="$(jq -r .commit_sha "$release_file")"
api_digest="$(jq -r .api_digest "$release_file")"
frontend_digest="$(jq -r .frontend_digest "$release_file")"
kubectl kustomize "$repo_root/k8s/overlays/production-dr" \
  | sed -e "s#registry.invalid/distributed-trading/trading-api:bootstrap#$api_image#g" \
        -e "s#registry.invalid/distributed-trading/frontend:bootstrap#$frontend_image#g" \
  | kubectl apply -f -
dr_active=true

# DR uses the same Kubernetes-only PostgreSQL credential as production. Never
# write the secret to Git or an artifact; copy its opaque object in-cluster.
if ! kubectl -n production-dr get secret postgres-credentials >/dev/null 2>&1; then
  kubectl --kubeconfig "$production_kubeconfig" -n production get secret postgres-credentials -o json \
    | jq 'del(.metadata.uid,.metadata.resourceVersion,.metadata.creationTimestamp,.metadata.annotations,.metadata.managedFields) | .metadata.namespace="production-dr"' \
    | kubectl apply -f -
fi

# A DR drill is an explicit, approved activation. It never changes the
# default overlay, whose replicas remain zero. Data services are restored
# before application workloads so the imported projection is not overwritten
# by a newly-started worker.
for workload in redis kafka postgres; do
  kubectl -n production-dr scale "statefulset/$workload" --replicas=1
done
kubectl -n production-dr scale deployment/redis-sentinel --replicas=1
kubectl -n production-dr rollout status statefulset/redis --timeout=10m
kubectl -n production-dr rollout status statefulset/kafka --timeout=10m
kubectl -n production-dr rollout status statefulset/postgres --timeout=10m
kubectl -n production-dr rollout status deployment/redis-sentinel --timeout=10m

postgres_pod="$(kubectl -n production-dr get pod -l app.kubernetes.io/name=postgres \
  -o jsonpath='{.items[0].metadata.name}')"
test -n "$postgres_pod"
kubectl -n production-dr exec "$postgres_pod" -- \
  psql -U trading -d trading -v ON_ERROR_STOP=1 \
  -c 'DROP SCHEMA IF EXISTS trading CASCADE;'
gzip -dc "$backup_file" | kubectl -n production-dr exec -i "$postgres_pod" -- \
  psql -U trading -d trading -v ON_ERROR_STOP=1

for workload in trading-api trading-worker frontend; do
  kubectl -n production-dr scale "deploy/$workload" --replicas=1
done
kubectl -n production-dr set env deploy/trading-api deploy/trading-worker \
  COMMIT_SHA="$commit_sha" IMAGE_DIGEST="$api_digest"
kubectl -n production-dr set env deploy/frontend \
  COMMIT_SHA="$commit_sha" IMAGE_DIGEST="$frontend_digest"
kubectl -n production-dr rollout status deployment/trading-api --timeout=10m
kubectl -n production-dr rollout status deployment/trading-worker --timeout=10m
kubectl -n production-dr rollout status deployment/frontend --timeout=10m
kubectl -n production-dr get pods -o wide

api_port_forward_log="${RUNNER_TEMP:-/tmp}/dr-api-port-forward.log"
kubectl -n production-dr port-forward service/trading-api 18080:8000 \
  >"$api_port_forward_log" 2>&1 &
api_port_forward_pid=$!
for _ in {1..30}; do
  if curl --fail --silent --show-error --max-time 2 \
    http://127.0.0.1:18080/healthz >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl --fail --silent --show-error --max-time 5 \
  http://127.0.0.1:18080/healthz >/dev/null
curl --fail --silent --show-error --max-time 5 \
  http://127.0.0.1:18080/readyz >/dev/null
curl --fail --silent --show-error --max-time 5 \
  http://127.0.0.1:18080/metrics >/dev/null
curl --fail --silent --show-error --max-time 5 \
  http://127.0.0.1:18080/api/market-data/ALPHA >/dev/null

order_body='{"account_id":"dr-demo-account","client_order_id":"dr-recovery-order","symbol":"ALPHA","side":"BUY","quantity":"1","limit_price":"100.00"}'
order_response="${RUNNER_TEMP:-/tmp}/dr-order-response.json"
order_status="$(curl --fail --silent --show-error --max-time 5 -o "$order_response" \
  -w '%{http_code}' -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: dr-recovery-order' -d "$order_body" \
  http://127.0.0.1:18080/api/orders)"
test "$order_status" = 202
order_id="$(jq -r .order_id "$order_response")"
test -n "$order_id" && test "$order_id" != null
for _ in {1..30}; do
  if [[ "$(curl --silent --show-error --max-time 5 -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:18080/api/orders/$order_id")" = 200 ]]; then
    break
  fi
  sleep 1
done
test "$(curl --silent --show-error --max-time 5 -o /dev/null -w '%{http_code}' \
  "http://127.0.0.1:18080/api/orders/$order_id")" = 200
test "$(curl --silent --show-error --max-time 5 -o /dev/null -w '%{http_code}' \
  http://127.0.0.1:18080/api/positions/dr-demo-account)" = 200
echo "DR business smoke passed: healthz/readyz/metrics/market-data=200, order=202, order query=200, positions=200"
echo "DR resources activated and PostgreSQL restored from backup $backup_file"
