#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cluster_name="${K3D_CLUSTER_NAME:-trading-production}"
runtime_root="${RUNTIME_ROOT:-$repo_root/.runtime}"
kubeconfig_dir="$runtime_root/kubeconfigs"
production_kubeconfig="$kubeconfig_dir/production"
tools_dir="${TOOLS_DIR:-$repo_root/.tools/bin}"
action="${1:-status}"

tool() {
  local name="$1"
  if [[ -x "$tools_dir/$name" ]]; then
    printf "%s" "$tools_dir/$name"
  else
    command -v "$name"
  fi
}

require_tools() {
  bash "$repo_root/scripts/ensure-local-tools.sh"
  export PATH="$tools_dir:$PATH"
}

require_docker() {
  if ! docker info >/dev/null 2>&1; then
    echo "Docker Desktop is not reachable. Start Docker Desktop and retry." >&2
    exit 1
  fi
}

write_production_kubeconfig() {
  mkdir -p "$kubeconfig_dir"
  "$(tool k3d)" kubeconfig get "$cluster_name" > "$production_kubeconfig"
  chmod 0600 "$production_kubeconfig"
  export KUBECONFIG="$production_kubeconfig"
}

label_production_nodes() {
  local zones=(local-a local-b local-c)
  local index
  for index in 0 1 2; do
    kubectl label node "k3d-${cluster_name}-server-${index}" \
      "topology.kubernetes.io/zone=${zones[$index]}" --overwrite
  done
}

create_vclusters() {
  export KUBECONFIG="$production_kubeconfig"
  kubectl apply -f "$repo_root/gitops/platform/namespaces.yaml"
  if ! kubectl -n vcluster-nonprod get statefulset nonprod >/dev/null 2>&1; then
    "$(tool vcluster)" create nonprod \
      --namespace vcluster-nonprod --connect=false --skip-wait \
      --values "$repo_root/k8s/local/vcluster-nonprod-values.yaml"
  fi
  if ! kubectl -n vcluster-dr get statefulset dr >/dev/null 2>&1; then
    "$(tool vcluster)" create dr \
      --namespace vcluster-dr --connect=false --skip-wait \
      --values "$repo_root/k8s/local/vcluster-dr-values.yaml"
  fi
}

ensure_prometheus_webhook_secret() {
  if [[ -n "$(kubectl -n observability get secret kube-prometheus-stack-admission \
      -o jsonpath='{.data.cert}:{.data.key}' 2>/dev/null || true)" ]]; then
    return 0
  fi
  local tmp_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/prom-webhook.XXXXXX")"
  trap 'rm -rf "$tmp_dir"' RETURN
  openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
    -keyout "$tmp_dir/key" -out "$tmp_dir/cert" \
    -subj "/CN=kube-prometheus-stack-operator.observability.svc" \
    >/dev/null 2>&1
  kubectl -n observability create secret generic kube-prometheus-stack-admission \
    --from-file=cert="$tmp_dir/cert" --from-file=key="$tmp_dir/key" \
    --dry-run=client -o yaml | kubectl apply -f -
  rm -rf "$tmp_dir"
  trap - RETURN
}

set_argocd_resource_bounds() {
  local resource_kind="$1"
  local resource_name="$2"
  local container_name="$3"
  local requests="$4"
  local limits="$5"
  if kubectl -n argocd get "$resource_kind" "$resource_name" >/dev/null 2>&1; then
    kubectl -n argocd set resources "$resource_kind/$resource_name" \
      --containers="$container_name" --requests="$requests" --limits="$limits"
  fi
}

ensure_argocd_resource_bounds() {
  # Gatekeeper requires requests/limits on every non-exempt Pod. Keep the
  # GitOps control plane lightweight instead of weakening the admission rule.
  set_argocd_resource_bounds deployment argocd-repo-server argocd-repo-server \
    cpu=100m,memory=128Mi cpu=500m,memory=512Mi
  set_argocd_resource_bounds statefulset argocd-application-controller argocd-application-controller \
    cpu=100m,memory=128Mi cpu=500m,memory=512Mi
  set_argocd_resource_bounds deployment argocd-applicationset-controller argocd-applicationset-controller \
    cpu=25m,memory=64Mi cpu=200m,memory=256Mi
  set_argocd_resource_bounds deployment argocd-notifications-controller argocd-notifications-controller \
    cpu=25m,memory=64Mi cpu=200m,memory=256Mi
}

install_platform_controllers() {
  export KUBECONFIG="$production_kubeconfig"
  kubectl apply -k "$repo_root/gitops/platform"
  if command -v flux >/dev/null 2>&1 || [[ -x "$tools_dir/flux" ]]; then
    "$(tool flux)" install --namespace=flux-system --network-policy=false
  else
    echo "Flux CLI is not installed; platform namespaces were applied."
  fi
  if ! kubectl -n argocd get deployment argocd-server >/dev/null 2>&1; then
    local argocd_manifest="$repo_root/k8s/local/argocd-install.yaml"
    if [[ -f "$argocd_manifest" ]]; then
      kubectl apply -n argocd -f "$argocd_manifest"
    else
      kubectl apply -n argocd -f \
        "${ARGOCD_MANIFEST_URL:-https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.3/manifests/install.yaml}"
    fi
  fi
  # CRDs must exist before Flux and Argo custom resources are applied.
  ensure_argocd_resource_bounds
  kubectl -n argocd rollout status deployment/argocd-server --timeout=10m
  kubectl apply -k "$repo_root/observability"
  ensure_prometheus_webhook_secret
  bash "$repo_root/scripts/install-security-controls.sh"
  if kubectl api-resources --api-group=source.toolkit.fluxcd.io >/dev/null 2>&1; then
    kubectl apply -f "$repo_root/gitops/platform/helm-repositories.yaml"
    kubectl apply -f "$repo_root/gitops/platform/helm-releases.yaml"
  fi
  bash "$repo_root/scripts/register-local-argocd-clusters.sh"
  kubectl apply -f "$repo_root/gitops/argocd/applications.yaml"
}

up() {
  require_tools
  require_docker
  mkdir -p "$runtime_root" "$kubeconfig_dir" "$runtime_root/backups"
  if ! "$(tool k3d)" cluster get "$cluster_name" >/dev/null 2>&1; then
    "$(tool k3d)" cluster create --config "$repo_root/k8s/local/k3d-config.yaml"
  fi
  write_production_kubeconfig
  label_production_nodes
  create_vclusters
  install_platform_controllers
  echo "Local platform is ready for GitOps deployment."
}

status() {
  if command -v docker >/dev/null 2>&1; then
    docker info --format "Docker={{.ServerVersion}}" 2>/dev/null || echo "Docker=unavailable"
  fi
  if command -v k3d >/dev/null 2>&1 || [[ -x "$tools_dir/k3d" ]]; then
    "$(tool k3d)" cluster list || true
  else
    echo "k3d=not-installed"
  fi
  if [[ -s "$production_kubeconfig" ]]; then
    KUBECONFIG="$production_kubeconfig" kubectl get nodes -o wide || true
    KUBECONFIG="$production_kubeconfig" kubectl get namespaces || true
  fi
}

pause_platform() {
  require_tools
  require_docker
  "$(tool k3d)" cluster stop "$cluster_name"
}

resume_platform() {
  require_tools
  require_docker
  "$(tool k3d)" cluster start "$cluster_name"
  write_production_kubeconfig
}

backup() {
  require_tools
  require_docker
  test -s "$production_kubeconfig"
  export KUBECONFIG="$production_kubeconfig"
  mkdir -p "$runtime_root/backups"
  local backup_path="$runtime_root/backups/postgres-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
  local pod
  pod="$(kubectl -n production get pods -l app.kubernetes.io/name=postgres \
    -o jsonpath="{.items[0].metadata.name}")"
  test -n "$pod"
  kubectl -n production exec "$pod" -- pg_dump -U trading -d trading | gzip > "$backup_path"
  chmod 0600 "$backup_path"
  echo "$backup_path"
}

assert_platform() {
  require_tools
  require_docker
  test -s "$production_kubeconfig"
  export KUBECONFIG="$production_kubeconfig"
  test "$(kubectl get nodes --no-headers | wc -l | tr -d " ")" = "3"
  kubectl wait --for=condition=Ready nodes --all --timeout=120s
  for namespace in production observability flux-system argocd gatekeeper-system falco vcluster-nonprod vcluster-dr; do
    kubectl get namespace "$namespace" >/dev/null
  done
}

destroy() {
  require_tools
  require_docker
  if [[ "${ALLOW_LOCAL_DESTROY:-false}" != "true" ]]; then
    echo "Refusing destroy: set ALLOW_LOCAL_DESTROY=true after backup and approval." >&2
    exit 1
  fi
  "$(tool k3d)" cluster delete "$cluster_name"
}

case "$action" in
  up) up ;;
  status) status ;;
  pause) pause_platform ;;
  resume) resume_platform ;;
  backup) backup ;;
  assert) assert_platform ;;
  destroy) destroy ;;
  *) echo "Usage: $0 {up|status|pause|resume|backup|assert|destroy}" >&2; exit 2 ;;
esac
