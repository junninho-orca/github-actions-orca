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
variable "region"     { type = string }

# ------------------------------------------------------------
# Cloud SQL (PostgreSQL) — multiple intentional misconfigurations
# ------------------------------------------------------------

resource "google_sql_database_instance" "postgres" {
  name             = "orca-demo-db-${var.env}"
  database_version = "POSTGRES_14"
  region           = var.region
  project          = var.project_id

  # MISCONFIGURATION: deletion protection disabled — single API call drops the instance
  deletion_protection = false

  settings {
    tier = "db-f1-micro"

    # MISCONFIGURATION: automated backups disabled — no recovery point
    backup_configuration {
      enabled = false
    }

    ip_configuration {
      # MISCONFIGURATION: SSL not required — connections can be unencrypted
      ssl_mode = "ALLOW_UNENCRYPTED_AND_ENCRYPTED"

      # MISCONFIGURATION: public IPv4 address assigned
      ipv4_enabled = true

      # MISCONFIGURATION: private network not configured — no VPC isolation

      # MISCONFIGURATION: authorized network allows all internet traffic
      authorized_networks {
        name  = "all-internet"
        value = "0.0.0.0/0"
      }
    }

    # MISCONFIGURATION: key security database flags omitted
    # log_connections, log_disconnections, log_lock_waits all off by default

    # MISCONFIGURATION: no maintenance window configured

    # MISCONFIGURATION: insights config disabled
    insights_config {
      query_insights_enabled = false
    }
  }
}

resource "google_sql_database" "app" {
  name     = "orcademo"
  instance = google_sql_database_instance.postgres.name
  project  = var.project_id
}

# MISCONFIGURATION: hardcoded plaintext password (also a secrets finding)
resource "google_sql_user" "admin" {
  name     = "dbadmin"
  instance = google_sql_database_instance.postgres.name
  project  = var.project_id
  password = "Sup3rS3cret!Demo"
}

output "db_connection_name" { value = google_sql_database_instance.postgres.connection_name }
output "db_public_ip"       { value = google_sql_database_instance.postgres.public_ip_address }
