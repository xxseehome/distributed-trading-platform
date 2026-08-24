#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="${1:?action is required}"
export KUBECONFIG="${KUBECONFIG:-$repo_root/.runtime/kubeconfigs/production}"
test -s "$KUBECONFIG"

port_forward_pid=""
cleanup() {
  if [[ -n "$port_forward_pid" ]]; then
    kill "$port_forward_pid" 2>/dev/null || true
    wait "$port_forward_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

restart_workload() {
  local workload="$1"
  kubectl -n production rollout restart "deploy/$workload"
  kubectl -n production rollout status "deploy/$workload" --timeout=5m
}

set_kill_switch() {
  local enabled="$1" token response status
  token="$(kubectl -n production get secret trading-admin \
    -o jsonpath='{.data.token}' | base64 --decode)"
  test -n "$token"
  kubectl -n production port-forward service/trading-api 18081:8000 \
    >/tmp/trading-ops-port-forward.log 2>&1 &
  port_forward_pid=$!
  for _ in {1..30}; do
    curl --silent --show-error --max-time 2 \
      http://127.0.0.1:18081/healthz >/dev/null 2>&1 && break
    sleep 1
  done
  response="$(curl --silent --show-error --max-time 5 -o /dev/null -w '%{http_code}' \
    -H "X-Admin-Token: $token" -H 'Content-Type: application/json' \
    -d "{\"enabled\":$enabled,\"reason\":\"approved local operations\"}" \
    http://127.0.0.1:18081/api/admin/kill-switch)"
  status="$response"
  unset token
  test "$status" = 200
  echo "kill-switch action completed: enabled=$enabled, HTTP=$status"
}

case "$action" in
  kill-switch-on) set_kill_switch true ;;
  kill-switch-off) set_kill_switch false ;;
  restart-api) restart_workload trading-api ;;
  consumer-resume) restart_workload trading-worker ;;
  *)
    echo "Usage: $0 {kill-switch-on|kill-switch-off|restart-api|consumer-resume}" >&2
    exit 2
    ;;
esac
