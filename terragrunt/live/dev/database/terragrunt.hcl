locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  project_id = local.project_vars.locals.gcp_project_id
  region     = local.region_vars.locals.gcp_region
  env        = local.env_vars.locals.env
}

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules/database"
}

inputs = {
  env        = local.env
  project_id = local.project_id
  region     = local.region
}
