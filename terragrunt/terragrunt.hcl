# Root terragrunt configuration — applies to all child modules
#
# Intentional misconfigurations for Orca IaC demo:
#   - State bucket has no customer-managed encryption key
#   - State bucket has no versioning
#   - No uniform bucket-level access on state bucket

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  project_id = local.project_vars.locals.gcp_project_id
  region     = local.region_vars.locals.gcp_region
}

# Use generate instead of remote_state so Terragrunt writes the backend config
# file without trying to create or validate a GCS bucket. This lets CI generate
# terraform plan files with TF_CLI_ARGS_init="-backend=false" and no storage
# permissions — while real deployments still get a proper GCS backend.
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "gcs" {
    bucket  = "orca-demo-tfstate-${local.project_id}"
    prefix  = "${path_relative_to_include()}/terraform.tfstate"
    project = "${local.project_id}"

    # MISCONFIGURATION: no customer-managed encryption key
    # MISCONFIGURATION: no uniform bucket-level access
  }
}
EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "google" {
  project = "${local.project_id}"
  region  = "${local.region}"
}
EOF
}
