# shellcheck shell=bash disable=SC2034
# Shared settings for up.sh, down.sh and test.sh.
PROJECT="${1:-${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}}"
REGION="${REGION:-us-central1}"
TF="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"
CHART="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="$REGION-docker.pkg.dev/$PROJECT/apps/shop-api"
[ -n "$PROJECT" ] || { echo "Usage: $0 <PROJECT_ID>"; exit 1; }
step() { echo; echo "==> $*"; }
