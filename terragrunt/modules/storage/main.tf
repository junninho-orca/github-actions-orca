terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

variable "env"         { type = string }
variable "project_id"  { type = string }
variable "region"      { type = string }
variable "bucket_name" { type = string }

# ------------------------------------------------------------
# Cloud Storage bucket — multiple intentional misconfigurations
# ------------------------------------------------------------

resource "google_storage_bucket" "data" {
  name     = "${var.bucket_name}-${var.env}"
  location = var.region
  project  = var.project_id

  # MISCONFIGURATION: uniform bucket-level access disabled — allows per-object ACLs
  # which can silently make individual objects public
  uniform_bucket_level_access = false

  # MISCONFIGURATION: public access prevention not enforced
  public_access_prevention = "inherited"

  # MISCONFIGURATION: versioning disabled — no recovery from accidental deletes
  # versioning { enabled = true }  omitted intentionally

  # MISCONFIGURATION: no retention policy

  # MISCONFIGURATION: no access logging configured
  # logging { log_bucket = "..." }  omitted intentionally

  # MISCONFIGURATION: no lifecycle rules to manage object expiry

  force_destroy = true
}

# MISCONFIGURATION: grants public read to all unauthenticated internet users
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.data.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"  # MISCONFIGURATION
}

# MISCONFIGURATION: grants public write via legacy ACL role
resource "google_storage_bucket_iam_member" "public_write" {
  bucket = google_storage_bucket.data.name
  role   = "roles/storage.legacyBucketWriter"
  member = "allAuthenticatedUsers"  # MISCONFIGURATION
}

# Second bucket for logs — also misconfigured
resource "google_storage_bucket" "logs" {
  name                        = "${var.bucket_name}-logs-${var.env}"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = false  # MISCONFIGURATION
  public_access_prevention    = "inherited"
  force_destroy               = true
}

output "bucket_name" { value = google_storage_bucket.data.name }
output "bucket_url"  { value = google_storage_bucket.data.url }
