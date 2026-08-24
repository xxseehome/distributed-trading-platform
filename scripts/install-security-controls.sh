#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$repo_root/.runtime/kubeconfigs/production}"
test -s "$KUBECONFIG"

# Gatekeeper is installed from a pinned upstream release.  The local
# experiment does not use a cloud admission service.
kubectl apply -f \
  https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.17.1/deploy/gatekeeper.yaml
kubectl wait --for=condition=Established crd/constrainttemplates.templates.gatekeeper.sh --timeout=5m
# Register the ConstraintTemplate first; the Constraint kind is not served
# until Gatekeeper has created the generated CRD.
awk 'BEGIN { exit_code = 0 } /^---$/ { exit } { print }' \
  "$repo_root/gitops/platform/gatekeeper.yaml" | kubectl apply -f -
kubectl wait --for=condition=Established crd/k8srequiredresources.constraints.gatekeeper.sh --timeout=5m
kubectl apply -f "$repo_root/gitops/platform/gatekeeper.yaml"
kubectl apply -f "$repo_root/gitops/platform/falco-rules.yaml"

# The upstream manifest uses Always, which makes a locally imported image look
# unavailable to a Docker Desktop node.  Keep the pinned image, but prefer the
# image already loaded into each k3d server and let the Deployment roll once.
for deployment in gatekeeper-audit gatekeeper-controller-manager; do
  kubectl -n gatekeeper-system patch deployment "$deployment" --type=json \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"IfNotPresent"}]'
done
kubectl -n gatekeeper-system rollout status deployment/gatekeeper-audit --timeout=5m
kubectl -n gatekeeper-system rollout status deployment/gatekeeper-controller-manager --timeout=5m

echo "Gatekeeper constraints and Falco rules are installed."
echo "Falco eBPF runtime detection remains an explicit Docker Desktop limitation."
