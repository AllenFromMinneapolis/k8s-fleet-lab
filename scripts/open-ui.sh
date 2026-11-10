#!/usr/bin/env bash
# Opens Argo CD, Grafana and the store app for one cluster. Ctrl+C to stop.
set -euo pipefail
NAME="${1:?usage: open-ui.sh <name>}"
CTX="k3d-$NAME"
PW=$(kubectl --context "$CTX" -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
kubectl --context "$CTX" -n argocd port-forward svc/argocd-server 8080:80 >/dev/null 2>&1 &
kubectl --context "$CTX" -n monitoring port-forward svc/monitoring-grafana 3000:80 >/dev/null 2>&1 &
kubectl --context "$CTX" -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 >/dev/null 2>&1 &
kubectl --context "$CTX" -n store-apps port-forward svc/store-app 8081:80 >/dev/null 2>&1 &
trap 'kill $(jobs -p) 2>/dev/null' EXIT
echo "Argo CD    http://localhost:8080   user: admin   password: $PW"
echo "Grafana    http://localhost:3000   user: admin   password: fleetlab"
echo "Prometheus http://localhost:9090   (no login)"
echo "Store app  http://localhost:8081"
echo "Vault      http://localhost:8200   token: root"
echo "Press Ctrl+C to stop."
wait
