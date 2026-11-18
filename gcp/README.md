# Secure delivery on GCP (GKE Autopilot)

A small Go API deployed to Google Kubernetes Engine through a security-scanning pipeline.
Practice for application security and platform roles at a GCP shop.

| Piece | Where | Security / ops point |
|---|---|---|
| Infrastructure as Code | `terraform/` | GKE Autopilot, Artifact Registry, Secret Manager, IAM, all in Terraform |
| No stored keys | `terraform/main.tf` | GitHub Actions logs in with Workload Identity Federation, only from `main` of this repo; pods use Workload Identity |
| Secrets | `app/secret.go` | API key read from Secret Manager at startup; value never in Git, image or Terraform state |
| Secure code | `app/main.go` | Parameterized SQL, constant-time key check, server timeouts, generic errors |
| Hardened container | `app/Dockerfile`, `chart/` | Distroless, non-root, read-only filesystem, no Linux capabilities |
| Pipeline | `.github/workflows/gcp-secure-pipeline.yml` | gosec (SAST), govulncheck (SCA), gitleaks (secrets), trivy (IaC + image); actions pinned to commit SHAs |
| Deploy | Helm | `chart/shop-api` and the OpenTelemetry Collector chart |
| Telemetry | `app/telemetry.go`, `otel-collector-values.yaml` | OTel Go SDK -> Collector -> Cloud Trace and Managed Service for Prometheus |

Pull requests only run the scans. Pushes to `main` scan, then build, push and deploy once the
three GitHub variables below are set.

## Set up (from your Mac)

```
brew install --cask google-cloud-sdk
brew tap hashicorp/tap && brew install hashicorp/tap/terraform
gcloud auth login
gcloud auth application-default login
gcloud config set project <PROJECT_ID>

cd gcp/terraform
terraform init
terraform apply -var project_id=<PROJECT_ID>            # about 10 minutes

# Add the secret value yourself, so it never goes through Terraform or Git:
openssl rand -hex 24 | gcloud secrets versions add shop-api-key --data-file=-
```

Copy the three `github_variables` from the Terraform output into GitHub: repo Settings >
Secrets and variables > Actions > Variables. Then GitHub > Actions > gcp-secure-pipeline >
Run workflow.

## Try it

```
gcloud container clusters get-credentials shop-lab --region us-central1
kubectl -n shop port-forward svc/shop-api 8085:80
KEY=$(gcloud secrets versions access latest --secret shop-api-key)
curl -H "X-API-Key: $KEY" "localhost:8085/products?name=co"            # coffee, cookie
curl -H "X-API-Key: $KEY" --get --data-urlencode "name=' OR '1'='1" localhost:8085/products   # [] - injection fails
curl "localhost:8085/products?name=co"                                   # 401 without the key
```

Traces: Cloud console > Trace explorer. Metrics: Monitoring > Metrics explorer, PromQL
`rate(product_searches_total[5m])`.

**See the pipeline block a bug:** on a branch, change the query in `app/main.go` to
`"SELECT id, name, price FROM products WHERE name LIKE '%" + name + "%'"` and open a pull
request. gosec fails the build with G202 (SQL string concatenation).

## Up and down with one command

```
gcp/scripts/up.sh <PROJECT_ID>     # build or repair everything, about 10-15 min for a new cluster
gcp/scripts/test.sh <PROJECT_ID>   # key check, SQL injection attempt, 401s, links to traces/metrics
gcp/scripts/down.sh <PROJECT_ID>   # delete the cluster (the cost); keep registry, secret, GitHub login
gcp/scripts/down.sh <PROJECT_ID> --all   # delete everything
```

`up.sh` checks billing, runs Terraform, adds the secret value if missing, and deploys the last
image the pipeline built and scanned. After `--all`, Google keeps the deleted GitHub identity pool
for 30 days and blocks re-creating it by name, so `up.sh` restores and re-imports it.

## Clean up (stops all charges)

```
cd gcp/terraform && terraform destroy -var project_id=<PROJECT_ID>
```
