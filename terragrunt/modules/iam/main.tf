terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

variable "env"        { type = string }
variable "project_id" { type = string }

# ------------------------------------------------------------
# IAM — multiple intentional misconfigurations
# ------------------------------------------------------------

# MISCONFIGURATION: grants primitive Owner role to all authenticated GCP users
resource "google_project_iam_binding" "owner_all_authenticated" {
  project = var.project_id
  role    = "roles/owner"

  members = [
    "allAuthenticatedUsers",  # MISCONFIGURATION: any Google account gets owner
  ]
}

resource "google_service_account" "app" {
  account_id   = "orca-demo-app-${var.env}"
  display_name = "Orca Demo App"
  project      = var.project_id
}

# MISCONFIGURATION: primitive Editor role — broad write access across all GCP APIs
resource "google_project_iam_member" "app_editor" {
  project = var.project_id
  role    = "roles/editor"  # MISCONFIGURATION: should use a least-privilege custom role
  member  = "serviceAccount:${google_service_account.app.email}"
}

# MISCONFIGURATION: creates a downloadable JSON key — long-lived credential
# that cannot be revoked without deleting the key
resource "google_service_account_key" "app" {
  service_account_id = google_service_account.app.name
  # key_algorithm defaults to KEY_ALG_RSA_2048 — no rotation possible
}

# MISCONFIGURATION: service account key exported as plaintext output,
# will appear in Terraform state and CI logs
output "service_account_key" {
  value     = google_service_account_key.app.private_key
  sensitive = false  # MISCONFIGURATION: should be sensitive = true
}

# MISCONFIGURATION: allows any identity in the project to impersonate this SA
resource "google_service_account_iam_binding" "impersonate_all" {
  service_account_id = google_service_account.app.name
  role               = "roles/iam.serviceAccountTokenCreator"

  members = [
    "allAuthenticatedUsers",  # MISCONFIGURATION
  ]
}

# MISCONFIGURATION: workload identity pool not scoped — allows all identities
resource "google_project_iam_member" "storage_admin_all" {
  project = var.project_id
  role    = "roles/storage.admin"  # MISCONFIGURATION: admin instead of objectAdmin
  member  = "allAuthenticatedUsers"
}

output "service_account_email" { value = google_service_account.app.email }
