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
