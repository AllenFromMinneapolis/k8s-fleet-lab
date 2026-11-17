data "google_project" "this" {}

locals {
  # Kubernetes service accounts get GCP permissions directly through Workload Identity (no keys).
  k8s_principal  = "principal://iam.googleapis.com/projects/${data.google_project.this.number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject"
  app_principal  = "${local.k8s_principal}/ns/shop/sa/shop-api"
  otel_principal = "${local.k8s_principal}/ns/otel/sa/otel-collector"
  # GitHub Actions runs from this repo get permissions through Workload Identity Federation (no keys).
  github_principal = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
  node_sa          = "serviceAccount:${data.google_project.this.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_service" "apis" {
  for_each = toset([
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "cloudtrace.googleapis.com",
    "monitoring.googleapis.com",
    "containerscanning.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# --- Image registry (Google also scans pushed images for vulnerabilities) ---
resource "google_artifact_registry_repository" "apps" {
  repository_id = "apps"
  location      = var.region
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

# --- GKE Autopilot: Google runs the nodes; Workload Identity is always on ---
resource "google_container_cluster" "lab" {
  name                = "shop-lab"
  location            = var.region
  enable_autopilot    = true
  deletion_protection = false
  depends_on          = [google_project_service.apis]
}

# --- Secret Manager: Terraform creates the empty secret; you add the value with gcloud,
#     so the value never lands in Terraform state or Git ---
resource "google_secret_manager_secret" "api_key" {
  secret_id = "shop-api-key"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

# --- Least privilege: each identity gets only what it needs ---
resource "google_secret_manager_secret_iam_member" "app_reads_secret" {
  secret_id  = google_secret_manager_secret.api_key.id
  role       = "roles/secretmanager.secretAccessor"
  member     = local.app_principal
  depends_on = [google_container_cluster.lab]
}

resource "google_project_iam_member" "otel" {
  for_each   = toset(["roles/cloudtrace.agent", "roles/monitoring.metricWriter"])
  project    = var.project_id
  role       = each.value
  member     = local.otel_principal
  depends_on = [google_container_cluster.lab]
}

resource "google_artifact_registry_repository_iam_member" "nodes_pull" {
  repository = google_artifact_registry_repository.apps.name
  location   = var.region
  role       = "roles/artifactregistry.reader"
  member     = local.node_sa
  depends_on = [google_container_cluster.lab]
}

resource "google_project_iam_member" "nodes_default" {
  project    = var.project_id
  role       = "roles/container.defaultNodeServiceAccount"
  member     = local.node_sa
  depends_on = [google_container_cluster.lab]
}

# --- GitHub Actions -> GCP with short-lived tokens, only from main of one repo ---
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  depends_on                = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  attribute_condition = "assertion.repository == '${var.github_repo}' && assertion.ref == 'refs/heads/main'"
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_artifact_registry_repository_iam_member" "github_push" {
  repository = google_artifact_registry_repository.apps.name
  location   = var.region
  role       = "roles/artifactregistry.writer"
  member     = local.github_principal
}

resource "google_project_iam_member" "github_deploy" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = local.github_principal
}
