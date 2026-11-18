#!/usr/bin/env bash
# Tear the GCP lab down.
#   gcp/scripts/down.sh [PROJECT_ID]         deletes the cluster (the only real cost) and its IAM;
#                                            keeps the registry, secret and GitHub login (pennies a month)
#   gcp/scripts/down.sh [PROJECT_ID] --all   deletes everything Terraform created
# Either way, gcp/scripts/up.sh brings it all back.
set -euo pipefail
ALL=false
ARGS=()
for a in "$@"; do [ "$a" = --all ] && ALL=true || ARGS+=("$a"); done
set -- "${ARGS[@]+"${ARGS[@]}"}"
source "$(dirname "$0")/common.sh"
START=$SECONDS

terraform -chdir="$TF" init -input=false >/dev/null
if $ALL; then
  step "Destroying everything in $PROJECT (about 5-10 minutes)"
  terraform -chdir="$TF" destroy -input=false -auto-approve -var project_id="$PROJECT" -var region="$REGION"
else
  step "Destroying the cluster in $PROJECT (about 5-10 minutes)"
  terraform -chdir="$TF" destroy -input=false -auto-approve -var project_id="$PROJECT" -var region="$REGION" \
    -target=google_container_cluster.lab
fi
step "Down in $(( (SECONDS - START) / 60 )) min. Remaining resources: terraform -chdir=$TF state list"
