output "github_variables" {
  description = "Add these as GitHub repo variables (Settings > Secrets and variables > Actions > Variables)"
  value = {
    GCP_PROJECT_ID   = var.project_id
    GCP_REGION       = var.region
    GCP_WIF_PROVIDER = google_iam_workload_identity_pool_provider.github.name
  }
}
