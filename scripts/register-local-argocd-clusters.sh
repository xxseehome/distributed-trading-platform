#!/usr/bin/env bash
set -euo pipefail

# Register the three local Kubernetes API servers in Argo CD.
#
# This is deliberately runtime-only: short-lived service-account tokens are
# generated from the vClusters and stored as Argo CD cluster Secrets.  No
# kubeconfig or token is written to the repository or to a GitHub artifact.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tools_dir="${TOOLS_DIR:-$repo_root/.tools/bin}"
production_kubeconfig="${LOCAL_PRODUCTION_KUBECONFIG:-$repo_root/.runtime/kubeconfigs/production}"
runtime_root="${RUNTIME_ROOT:-$repo_root/.runtime}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/argocd-clusters.XXXXXX")"
vcluster_pid=""

cleanup() {
  stop_vcluster
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

stop_vcluster() {
  if [[ -n "$vcluster_pid" ]]; then
    kill "$vcluster_pid" 2>/dev/null || true
    wait "$vcluster_pid" 2>/dev/null || true
    vcluster_pid=""
  fi
}

tool() {
  local name="$1"
  if [[ -x "$tools_dir/$name" ]]; then
    printf '%s' "$tools_dir/$name"
  else
    command -v "$name"
  fi
}

test -s "$production_kubeconfig"
export KUBECONFIG="$production_kubeconfig"

connect_vcluster() {
  local name="$1" namespace="$2" output="$3"
  : > "$output"
  "$(tool vcluster)" connect "$name" --namespace "$namespace" \
    --print --background-proxy=false > "$output" 2>"$output.log" &
  vcluster_pid=$!
  for _ in {1..60}; do
    if grep -q '^current-context:' "$output"; then
      sed '/^Forwarding from/,$d' "$output" > "$output.cleaned"
      mv "$output.cleaned" "$output"
      chmod 0600 "$output"
      for _ in {1..30}; do
        if KUBECONFIG="$output" kubectl version --request-timeout=3s >/dev/null 2>&1; then
          return 0
        fi
        sleep 1
      done
      echo "Timed out waiting for vCluster API $name" >&2
      return 1
    fi
    sleep 1
  done
  cat "$output.log" >&2 || true
  echo "Timed out connecting to vCluster $name" >&2
  return 1
}

ensure_manager() {
  local kubeconfig="$1" namespaces="$2"
  KUBECONFIG="$kubeconfig" kubectl apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
YAML
  local namespace
  IFS=, read -r -a namespace_list <<< "$namespaces"
  for namespace in "${namespace_list[@]}"; do
    KUBECONFIG="$kubeconfig" kubectl create namespace "$namespace" \
      --dry-run=client -o yaml | KUBECONFIG="$kubeconfig" kubectl apply -f - >/dev/null
    KUBECONFIG="$kubeconfig" kubectl create rolebinding argocd-manager \
      --clusterrole=admin --serviceaccount=kube-system:argocd-manager \
      --namespace="$namespace" --dry-run=client -o yaml \
      | KUBECONFIG="$kubeconfig" kubectl apply -f - >/dev/null
    # Argo needs read-only discovery for CRDs in the managed namespace. Keep
    # write permissions on the existing namespace admin RoleBinding only.
    KUBECONFIG="$kubeconfig" kubectl apply --validate=false -f - >/dev/null <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argocd-read-namespaced-resources
  namespace: $namespace
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argocd-read-namespaced-resources
  namespace: $namespace
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: argocd-read-namespaced-resources
subjects:
  - kind: ServiceAccount
    name: argocd-manager
    namespace: kube-system
YAML
  done
}

cluster_secret() {
  local secret_name="$1" display_name="$2" server="$3" token="$4" ca_data="$5"
  local config
  config="$(jq -cn --arg token "$token" --arg ca "$ca_data" \
    '{bearerToken:$token,tlsClientConfig:{caData:$ca}}')"
  kubectl apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: $secret_name
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: $display_name
  server: $server
  config: '$config'
YAML
}

production_token="$(kubectl -n argocd create token argocd-application-controller --duration=24h)"
production_ca="$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
cluster_secret \
  local-production \
  production \
  https://kubernetes.default.svc \
  "$production_token" \
  "$production_ca"

for item in "nonprod:non-production:vcluster-nonprod:nonprod.vcluster-nonprod:local-non-production" \
            "dr:dr:vcluster-dr:dr.vcluster-dr:local-dr"; do
  IFS=: read -r name display_name namespace server secret_name <<< "$item"
  kubeconfig="$tmp_dir/$name.kubeconfig"
  connect_vcluster "$name" "$namespace" "$kubeconfig"
  if [[ "$name" == nonprod ]]; then
    manager_namespaces='dev,test,perf,staging'
  else
    manager_namespaces='production-dr'
  fi
  ensure_manager "$kubeconfig" "$manager_namespaces"
  token="$(KUBECONFIG="$kubeconfig" kubectl -n kube-system create token argocd-manager --duration=24h)"
  ca_data="$(KUBECONFIG="$kubeconfig" kubectl config view --raw \
    -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
  cluster_secret "$secret_name" "$display_name" "https://$server" "$token" "$ca_data"
  # Keep vCluster registrations namespaced and read-only at the discovery
  # boundary. Argo can manage only the application namespace and cannot
  # attempt cluster-scoped resources such as Namespace objects.
  kubectl -n argocd patch secret "$secret_name" --type=merge -p \
    "{\"stringData\":{\"namespaces\":\"$manager_namespaces\",\"clusterResources\":\"false\"}}" \
    >/dev/null
  stop_vcluster
done

echo "Argo CD local cluster registrations refreshed: production, non-production, DR."
