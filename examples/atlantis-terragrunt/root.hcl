############################################################
# Root Terragrunt config. Every unit under live/ includes this.
#
# Note what is NOT here: any resource. This file configures state and
# providers; the resources live in modules/, and the settings that decide
# whether those resources are safe live in each unit's `inputs`. That split is
# why the Orca scan runs against the *rendered plan* rather than these files.
############################################################

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  aws_region  = local.account_vars.locals.aws_region
  environment = local.env_vars.locals.environment
}

# ---------------------------------------------------------------------------
# Provider
#
# The `skip_*` settings and static dummy credentials let `terragrunt plan`
# render a complete plan with no AWS access at all, which is what makes this
# example demoable on a laptop or in a POV tenant without handing out cloud
# credentials. Delete the three skips and the static keys when you point this
# at a real account.
# ---------------------------------------------------------------------------
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.aws_region}"

      # --- demo mode: remove for real accounts -----------------------------
      access_key                  = "demo"
      secret_key                  = "demo"
      skip_credentials_validation = true
      skip_metadata_api_check     = true
      skip_requesting_account_id  = true
      # ---------------------------------------------------------------------
    }
  EOF
}

generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.5.0"
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 5.0"
        }
      }
    }
  EOF
}

# ---------------------------------------------------------------------------
# State
#
# Demo mode uses local state so no S3 bucket or DynamoDB table is needed.
# Swap in the commented S3 block for anything real.
# ---------------------------------------------------------------------------
remote_state {
  backend = "local"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    path = "${get_terragrunt_dir()}/terraform.tfstate"
  }

  # backend = "s3"
  # config = {
  #   bucket         = "my-terraform-state-${local.environment}"
  #   key            = "${path_relative_to_include()}/terraform.tfstate"
  #   region         = local.aws_region
  #   encrypt        = true
  #   dynamodb_table = "my-terraform-locks"
  # }
}

inputs = {
  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
    Repo        = "github-actions-orca"
  }
}
