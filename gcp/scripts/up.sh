#!/usr/bin/env bash
# Build the whole GCP lab: Terraform infrastructure, the secret value, then Helm deploys.
# Safe to run again at any time: it only adds what is missing.
# Usage: gcp/scripts/up.sh [PROJECT_ID]     (about 10-15 minutes when the cluster is new)
set -euo pipefail
source "$(dirname "$0")/common.sh"
START=$SECONDS

step "Checking billing on $PROJECT"
if [ "$(gcloud billing projects describe "$PROJECT" --format='value(billingEnabled)')" != "True" ]; then
  echo "Billing is not linked. Link it at https://console.cloud.google.com/billing/projects, then rerun."
  exit 1
fi
gcloud billing projects describe "$PROJECT" --format='value(billingAccountName)'

command -v gke-gcloud-auth-plugin >/dev/null || gcloud components install gke-gcloud-auth-plugin --quiet

step "Terraform init"
terraform -chdir="$TF" init -input=false >/dev/null

# After a full teardown Google keeps the GitHub identity pool "soft-deleted" for 30 days and
# blocks creating a new one with the same name, so bring the old one back instead.
pool=(gcloud iam workload-identity-pools --project "$PROJECT" --location global)
if [ "$("${pool[@]}" describe github --format='value(state)' 2>/dev/null)" = DELETED ]; then
  step "Restoring soft-deleted GitHub identity pool"
  "${pool[@]}" undelete github --quiet
fi
if [ "$("${pool[@]}" providers describe github-actions --workload-identity-pool github --format='value(state)' 2>/dev/null)" = DELETED ]; then
  "${pool[@]}" providers undelete github-actions --workload-identity-pool github --quiet
fi

# Anything that exists in GCP but not in Terraform state gets imported rather than re-created.
adopt() {
  local addr=$1 id=$2; shift 2
  [ -n "$(terraform -chdir="$TF" state list "$addr" 2>/dev/null)" ] && return 0
  "$@" >/dev/null 2>&1 || return 0
  echo "Importing existing $addr"
  terraform -chdir="$TF" import -input=false -var project_id="$PROJECT" "$addr" "$id" >/dev/null
}
P="projects/$PROJECT"
adopt google_iam_workload_identity_pool.github "$P/locations/global/workloadIdentityPools/github" \
  "${pool[@]}" describe github
adopt google_iam_workload_identity_pool_provider.github "$P/locations/global/workloadIdentityPools/github/providers/github-actions" \
  "${pool[@]}" providers describe github-actions --workload-identity-pool github
adopt google_artifact_registry_repository.apps "$P/locations/$REGION/repositories/apps" \
  gcloud artifacts repositories describe apps --project "$PROJECT" --location "$REGION"
adopt google_secret_manager_secret.api_key "$P/secrets/shop-api-key" \
  gcloud secrets describe shop-api-key --project "$PROJECT"
adopt google_container_cluster.lab "$P/locations/$REGION/clusters/shop-lab" \
  gcloud container clusters describe shop-lab --project "$PROJECT" --location "$REGION"

step "Terraform apply (a new cluster takes about 10 minutes)"
terraform -chdir="$TF" apply -input=false -auto-approve -var project_id="$PROJECT" -var region="$REGION"

step "Secret value"
if [ -z "$(gcloud secrets versions list shop-api-key --project "$PROJECT" --filter='state:ENABLED' --limit=1 --format='value(name)')" ]; then
  openssl rand -hex 24 | gcloud secrets versions add shop-api-key --project "$PROJECT" --data-file=- >/dev/null
  echo "Added a new random API key to Secret Manager"
else
  echo "Already set"
fi

step "Connecting kubectl to the cluster"
gcloud container clusters get-credentials shop-lab --project "$PROJECT" --location "$REGION"

TAG="$(gcloud artifacts docker images list "$IMAGE" --include-tags --sort-by=~UPDATE_TIME --limit=1 \
  --format='value(tags)' 2>/dev/null | sed 's/[,;].*//; s/ //g' || true)"
if [ -z "$TAG" ]; then
  step "No image in Artifact Registry yet"
  echo "Run the pipeline once to build, scan and deploy it:"
  echo "  GitHub > Actions > gcp-secure-pipeline > Run workflow"
  exit 0
fi

step "Deploying with Helm (image tag $TAG, already scanned by the pipeline)"
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts --force-update >/dev/null
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector --version 0.178.2 \
  -n otel --create-namespace -f "$CHART/otel-collector-values.yaml" --wait --timeout 10m
helm upgrade --install shop-api "$CHART/chart/shop-api" -n shop --create-namespace \
  --set image.repository="$IMAGE" --set image.tag="$TAG" \
  --set secretName="projects/$PROJECT/secrets/shop-api-key/versions/latest" \
  --wait --timeout 10m
kubectl get pods -n otel; kubectl get pods -n shop

step "Up in $(( (SECONDS - START) / 60 )) min. Try it: gcp/scripts/test.sh"
