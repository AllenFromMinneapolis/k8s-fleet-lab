#!/usr/bin/env bash
# Show the security behavior of the deployed API.
# Usage: gcp/scripts/test.sh [PROJECT_ID]
set -euo pipefail
source "$(dirname "$0")/common.sh"

kubectl -n shop port-forward svc/shop-api 8085:80 >/dev/null 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null' EXIT
for _ in $(seq 20); do curl -s -o /dev/null localhost:8085/healthz && break; sleep 0.5; done
KEY="$(gcloud secrets versions access latest --secret shop-api-key --project "$PROJECT")"

show() { echo; echo "$1"; shift; curl -s -w '  (HTTP %{http_code})\n' "$@"; }
show "1. Correct key from Secret Manager -> products" -H "X-API-Key: $KEY" "localhost:8085/products?name=co"
show "2. SQL injection attempt -> [] (input is data, not SQL)" -H "X-API-Key: $KEY" --get \
  --data-urlencode "name=' OR '1'='1" localhost:8085/products
show "3. No key -> 401" "localhost:8085/products?name=co"
show "4. Wrong key -> 401" -H "X-API-Key: wrong" "localhost:8085/products?name=co"
echo
echo "Traces: https://console.cloud.google.com/traces/explorer?project=$PROJECT"
echo "Metrics: https://console.cloud.google.com/monitoring/metrics-explorer?project=$PROJECT  (PromQL: rate(product_searches_total[5m]))"
