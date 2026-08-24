#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scenario="${1:?scenario is required}"
base_url="${2:-http://127.0.0.1:8080}"
route_host="${ROUTE_HOST:-bookstore.example.invalid}"
export KUBECONFIG="${KUBECONFIG:-$repo_root/.runtime/kubeconfigs/production}"
test -s "$KUBECONFIG"
if [[ "${ALLOW_LOCAL_FAULT:-false}" != true ]]; then
  echo "Fault injection requires the local-resilience Environment approval." >&2
  exit 1
fi

evidence_dir="$repo_root/.runtime/evidence/$(date -u +%Y%m%dT%H%M%SZ)-$scenario"
mkdir -p "$evidence_dir"
exec > >(tee "$evidence_dir/resilience.log") 2>&1

probe() {
  if [[ -n "$route_host" ]]; then
    curl --fail --silent --show-error --max-time 5 -H "Host: $route_host" \
      "$base_url/healthz" >/dev/null
  else
    curl --fail --silent --show-error --max-time 5 "$base_url/healthz" >/dev/null
  fi
}

probe_frontend() {
  if [[ -n "$route_host" ]]; then
    curl --fail --silent --show-error --max-time 5 -H "Host: $route_host" \
      "${base_url%/}/" >/dev/null
  else
    curl --fail --silent --show-error --max-time 5 "${base_url%/}/" >/dev/null
  fi
}

restore_server=""
restore_workload=""
cleanup() {
  set +e
  [[ -n "$restore_workload" ]] && eval "$restore_workload"
  [[ -n "$restore_server" ]] && eval "$restore_server"
}
trap cleanup EXIT

kubectl get nodes -o wide
probe

case "$scenario" in
  server)
    container="k3d-trading-production-server-0"
    docker inspect "$container" >/dev/null
    restore_server="docker start $container >/dev/null"
    docker stop "$container"
    kubectl wait --for=condition=Ready node --all --timeout=120s
    probe
    ;;
  pod)
    pod="$(kubectl -n production get pod -l app.kubernetes.io/name=trading-api \
      --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
    test -n "$pod"
    kubectl -n production delete pod "$pod" --wait=false
    kubectl -n production rollout status deploy/trading-api --timeout=5m
    probe
    ;;
  all-pods)
    for component in frontend trading-api trading-worker; do
      pod="$(kubectl -n production get pod -l "app.kubernetes.io/name=$component" \
        --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
      test -n "$pod"
      kubectl -n production delete pod "$pod" --wait=false
    done
    failures=0
    for _ in {1..20}; do
      probe || failures=$((failures + 1))
      probe_frontend || failures=$((failures + 1))
      sleep 1
    done
    echo "all-pods HTTP checks: 20 healthz + 20 frontend; failures=$failures"
    test "$failures" -eq 0
    for deployment in frontend trading-api trading-worker; do
      kubectl -n production rollout status "deploy/$deployment" --timeout=5m
    done
    ;;
  kafka)
    pod="$(kubectl -n production get pod -l app.kubernetes.io/name=kafka \
      --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
    test -n "$pod"
    kubectl -n production delete pod "$pod" --wait=false
    kubectl -n production rollout status statefulset/kafka --timeout=5m
    probe
    ;;
  redis)
    pod="$(kubectl -n production get pod -l app.kubernetes.io/name=redis \
      --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
    test -n "$pod"
    kubectl -n production delete pod "$pod" --wait=false
    kubectl -n production rollout status statefulset/redis --timeout=5m
    probe
    ;;
  postgres)
    restore_workload="kubectl -n production scale statefulset/postgres --replicas=1 >/dev/null"
    kubectl -n production scale statefulset/postgres --replicas=0
    # Order acceptance is checked through the API; historical projection is
    # expected to degrade while PostgreSQL is absent.
    probe
    ;;
  *)
    echo "Usage: $0 {server|pod|all-pods|kafka|redis|postgres} [base_url]" >&2
    exit 2
    ;;
esac

kubectl get pods -A -o wide
echo "Resilience scenario passed: $scenario"
