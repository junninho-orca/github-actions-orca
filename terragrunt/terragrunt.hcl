# Root terragrunt configuration — applies to all child modules
#
# Intentional misconfigurations for Orca IaC demo:
#   - Remote state GCS bucket has no customer-managed encryption key
#   - Remote state GCS bucket has no versioning
#   - No uniform bucket-level access on state bucket

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  project_id = local.project_vars.locals.gcp_project_id
  region     = local.region_vars.locals.gcp_region
}

remote_state {
  backend = "gcs"

  config = {
    bucket = "orca-demo-tfstate-${local.project_id}"
    prefix = "${path_relative_to_include()}/terraform.tfstate"

    # MISCONFIGURATION: no customer-managed encryption key for state bucket
    # encryption_key = ""  # omitted intentionally

    # MISCONFIGURATION: no uniform bucket-level access
    # uniform_bucket_level_access not set
  }
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
