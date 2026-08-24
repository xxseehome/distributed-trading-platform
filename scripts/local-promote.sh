#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
environment="${1:?environment is required}"
release_file="${2:?release.json path is required}"
runtime_kubeconfig="${LOCAL_PRODUCTION_KUBECONFIG:-$repo_root/.runtime/kubeconfigs/production}"
test -s "$release_file"

vcluster_pid=""
cleanup_vcluster() {
  if [[ -n "$vcluster_pid" ]]; then
    kill "$vcluster_pid" 2>/dev/null || true
    wait "$vcluster_pid" 2>/dev/null || true
  fi
}
trap cleanup_vcluster EXIT

connect_vcluster_kubeconfig() {
  local name="$1" namespace="$2" output="$3"
  : > "$output"
  vcluster connect "$name" --namespace "$namespace" --insecure \
    --print --background-proxy=false > "$output" 2>"$output.log" &
  vcluster_pid=$!
  for _ in {1..60}; do
    if grep -q '^current-context:' "$output"; then
      # vcluster writes its port-forward notices to stdout after the YAML.
      # Keep only the kubeconfig document for kubectl consumers.
      sed '/^Forwarding from/,$d' "$output" > "$output.cleaned"
      mv "$output.cleaned" "$output"
      chmod 0600 "$output"
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for vCluster kubeconfig: $name" >&2
  cat "$output.log" >&2 || true
  return 1
}

case "$environment" in
  production)
    target_kubeconfig="$runtime_kubeconfig"
    ;;
  dev|test|perf|staging)
    target_kubeconfig="${RUNNER_TEMP:-/tmp}/vcluster-nonprod-${environment}.kubeconfig"
    connect_vcluster_kubeconfig nonprod vcluster-nonprod "$target_kubeconfig"
    ;;
  production-dr)
    target_kubeconfig="${RUNNER_TEMP:-/tmp}/vcluster-dr.kubeconfig"
    connect_vcluster_kubeconfig dr vcluster-dr "$target_kubeconfig"
    ;;
  *)
    echo "Unsupported promotion environment: $environment" >&2
    exit 2
    ;;
esac

chmod 0600 "$target_kubeconfig"
export KUBECONFIG="$target_kubeconfig"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'KUBECONFIG=%s\n' "$target_kubeconfig" >> "$GITHUB_ENV"
fi
api_image="$(jq -r .api_image "$release_file")"
frontend_image="$(jq -r .frontend_image "$release_file")"
commit_sha="$(jq -r .commit_sha "$release_file")"
api_digest="$(jq -r .api_digest "$release_file")"
test "$api_image" != "null"
test "$frontend_image" != "null"
test "$commit_sha" != "null"

kubectl kustomize "$repo_root/k8s/overlays/$environment" \
  | sed -e "s#registry.invalid/distributed-trading/trading-api:bootstrap#$api_image#g" \
        -e "s#registry.invalid/distributed-trading/frontend:bootstrap#$frontend_image#g" \
  | kubectl apply -f -

if [[ "$environment" != production-dr ]]; then
  for deployment in trading-api trading-worker; do
    kubectl -n "$environment" set env "deploy/$deployment" \
      COMMIT_SHA="$commit_sha" IMAGE_DIGEST="$api_digest"
  done
fi

# DR remains dormant unless the DR drill explicitly scales it up.
if [[ "$environment" != production-dr ]]; then
  for deployment in trading-api trading-worker frontend; do
    kubectl -n "$environment" rollout status "deploy/$deployment" --timeout=10m
  done
fi
printf 'environment=%s\napi_image=%s\nfrontend_image=%s\n' \
  "$environment" "$api_image" "$frontend_image"
