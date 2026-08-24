#!/usr/bin/env bash
set -euo pipefail

plan_file="docs/plan-local-trading-system.md"
base_ref="${PLAN_SYNC_BASE_REF:-origin/${GITHUB_BASE_REF:-main}}"

if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  # A freshly copied local workspace can intentionally have no Git history or
  # remote. CI still enforces the comparison against origin/main; local mode
  # records the limitation instead of failing before any validation runs.
  if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "plan-sync: no local base commit; skipped in bootstrap workspace"
    exit 0
  fi
  echo "plan-sync: base ref $base_ref is unavailable" >&2
  exit 1
fi

changed=()
while IFS= read -r path; do
  changed+=("$path")
done < <(git diff --name-only "$base_ref"...HEAD)
implementation_change=false
plan_changed=false
if ((${#changed[@]} > 0)); then
  for path in "${changed[@]}"; do
    [[ "$path" == "$plan_file" ]] && plan_changed=true
    case "$path" in
      .github/*|ansible/*|backend/*|frontend/*|gitops/*|k8s/*|observability/*|scripts/*|terraform/*)
        implementation_change=true
        ;;
    esac
  done
fi

if [[ "$implementation_change" == true && "$plan_changed" != true ]]; then
  echo "Implementation files changed without $plan_file" >&2
  printf "Changed implementation paths:\n%s\n" "${changed[@]}" >&2
  exit 1
fi
echo "plan-sync: implementation_change=$implementation_change plan_changed=$plan_changed"
