variable "project_id" {
  description = "Your GCP project ID"
  type        = string
}

variable "region" {
  description = "Where everything runs"
  type        = string
  default     = "us-central1"
}

variable "github_repo" {
  description = "The only GitHub repo allowed to deploy (owner/name)"
  type        = string
  default     = "AllenFromMinneapolis/k8s-fleet-lab"
}
