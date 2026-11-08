#!/usr/bin/env bash
# One-line health summary for every store cluster: the "fleet dashboard" in miniature.
set -uo pipefail
printf "%-12s %-10s %-28s %s\n" CLUSTER REGION "ARGO APPS (synced/healthy)" STORE-APP
for ctx in $(kubectl config get-contexts -o name | grep '^k3d-'); do
  name="${ctx#k3d-}"
  region=$(kubectl --context "$ctx" get nodes -o jsonpath='{.items[0].metadata.labels.fleet-lab/region}' 2>/dev/null)
  apps=$(kubectl --context "$ctx" -n argocd get applications -o jsonpath='{range .items[*]}{.status.sync.status}/{.status.health.status}{"\n"}{end}' 2>/dev/null)
  total=$(printf "%s\n" "$apps" | grep -c . || true)
  good=$(printf "%s\n" "$apps" | grep -c '^Synced/Healthy$' || true)
  ready=$(kubectl --context "$ctx" -n store-apps get deploy store-app -o jsonpath='{.status.readyReplicas}/{.spec.replicas}' 2>/dev/null)
  printf "%-12s %-10s %-28s %s\n" "$name" "${region:--}" "$good/$total" "${ready:--} pods ready"
done
