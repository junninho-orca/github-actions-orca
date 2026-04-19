locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  project_id = local.project_vars.locals.gcp_project_id
  env        = local.env_vars.locals.env
}

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules/iam"
}

inputs = {
  env        = local.env
  project_id = local.project_id
}
