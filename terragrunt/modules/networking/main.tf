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
# VPC
# MISCONFIGURATION: auto_create_subnetworks creates subnets in every
# region, making it impossible to control the attack surface.
# ------------------------------------------------------------
resource "google_compute_network" "main" {
  name                    = "orca-demo-${var.env}"
  project                 = var.project_id
  auto_create_subnetworks = true  # MISCONFIGURATION
}

# MISCONFIGURATION: VPC flow logs disabled (log_config omitted entirely)
resource "google_compute_subnetwork" "main" {
  name          = "orca-demo-${var.env}"
  ip_cidr_range = "10.0.0.0/16"
  region        = var.region
  network       = google_compute_network.main.id
  project       = var.project_id

  # log_config omitted — no flow logs
}

# ------------------------------------------------------------
# Firewall rules
# ------------------------------------------------------------

# MISCONFIGURATION: SSH open to the entire internet
resource "google_compute_firewall" "allow_ssh" {
  name    = "orca-demo-allow-ssh-${var.env}"
  network = google_compute_network.main.id
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]  # MISCONFIGURATION
}

# MISCONFIGURATION: RDP open to the entire internet
resource "google_compute_firewall" "allow_rdp" {
  name    = "orca-demo-allow-rdp-${var.env}"
  network = google_compute_network.main.id
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["3389"]
  }

  source_ranges = ["0.0.0.0/0"]  # MISCONFIGURATION
}

# MISCONFIGURATION: all traffic allowed from anywhere
resource "google_compute_firewall" "allow_all" {
  name    = "orca-demo-allow-all-${var.env}"
  network = google_compute_network.main.id
  project = var.project_id

  allow {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]  # MISCONFIGURATION
}

# ------------------------------------------------------------
# Compute instance
# ------------------------------------------------------------
resource "google_compute_instance" "web" {
  name         = "orca-demo-web-${var.env}"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"
  project      = var.project_id

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      # MISCONFIGURATION: no customer-managed encryption key on boot disk
    }
  }

  network_interface {
    network    = google_compute_network.main.id
    subnetwork = google_compute_subnetwork.main.id

    # MISCONFIGURATION: ephemeral public IP assigned
    access_config {}
  }

  # MISCONFIGURATION: default service account with cloud-platform scope
  # (effectively grants all GCP API access)
  service_account {
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]  # MISCONFIGURATION
  }

  metadata = {
    # MISCONFIGURATION: interactive serial console enabled — allows unauthenticated access
    serial-port-enable = "true"
    # MISCONFIGURATION: OS Login not enforced (enable-oslogin omitted)
  }

  # MISCONFIGURATION: Shielded VM not configured (no secure boot, vTPM, or integrity monitoring)
}

output "network_id"    { value = google_compute_network.main.id }
output "subnetwork_id" { value = google_compute_subnetwork.main.id }
