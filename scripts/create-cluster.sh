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

# Each cluster needs about 3.5 GB. Stop before a second one starves the first (FORCE=1 to skip).
EXISTING=$(k3d cluster list --no-headers 2>/dev/null | awk -v n="$NAME" '$1!=n' | grep -c . || true)
MEM_GB=$(( $(docker info --format '{{.MemTotal}}') / 1024 / 1024 / 1024 ))
if [ "${FORCE:-0}" != 1 ] && [ "$EXISTING" -ge 1 ] && [ "$MEM_GB" -lt 11 ]; then
  echo "!! Docker Desktop has ${MEM_GB} GB and $EXISTING cluster(s) already running."
  echo "!! Another cluster needs about 12 GB total. Raise Docker memory, delete a cluster"
  echo "!! (k3d cluster delete <name>), or run with FORCE=1 to try anyway."
  exit 1
fi

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
  -f bootstrap/argocd-values.yaml >/dev/null

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
