#!/usr/bin/env bash
# Builds one store cluster from the template and hands it to Argo CD.
# Usage: ./scripts/create-cluster.sh store-001 east
set -euo pipefail
NAME="${1:?usage: create-cluster.sh <name> <region>}"
REGION="${2:-central}"
cd "$(dirname "$0")/.."

if [ -z "${REPO_URL:-}" ]; then
  REPO_URL="$(git remote get-url origin)"
  case "$REPO_URL" in git@github.com:*) REPO_URL="https://github.com/${REPO_URL#git@github.com:}";; esac
fi
BRANCH="${BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
echo ">> Cluster $NAME (region $REGION) will follow $REPO_URL @ $BRANCH"

docker ps --format '{{.Names}}' | grep -qx fleet-vault || ./scripts/start-vault.sh

echo ">> 1/4 Creating K3s cluster from cluster-template/k3d-cluster.yaml"
k3d cluster create "$NAME" --config cluster-template/k3d-cluster.yaml \
  --k3s-node-label "fleet-lab/region=$REGION@server:0"
CTX="k3d-$NAME"

echo ">> 2/4 Installing Argo CD"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
helm upgrade --install --kube-context "$CTX" argocd argo/argo-cd --version 10.17.0 \
  -n argocd --create-namespace --wait --timeout 10m \
  --set 'configs.params.server\.insecure=true' \
  --set dex.enabled=false --set notifications.enabled=false >/dev/null

echo ">> 3/4 Giving the cluster its Vault token"
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl --context "$CTX" apply -f - >/dev/null
kubectl --context "$CTX" -n external-secrets create secret generic vault-token --from-literal=token=root \
  --dry-run=client -o yaml | kubectl --context "$CTX" apply -f - >/dev/null

echo ">> 4/4 Pointing Argo CD at Git (from here on, Git is in charge)"
kubectl --context "$CTX" apply -f - <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  source:
    repoURL: $REPO_URL
    targetRevision: $BRANCH
    path: fleet/root
    helm:
      valuesObject:
        repoURL: $REPO_URL
        targetRevision: $BRANCH
        clusterName: $NAME
        region: $REGION
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML

echo
echo "Done. Argo CD is now installing everything. Watch it with:  k9s --context k3d-$NAME"
echo "Open the web screens with:  ./scripts/open-ui.sh $NAME"
