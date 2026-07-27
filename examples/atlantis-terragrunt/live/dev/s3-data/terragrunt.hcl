# dev: takes the module's secure defaults. This unit is the control case —
# `atlantis plan` here should pass the Orca gate.

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/examples/atlantis-terragrunt/modules//s3-bucket"
}

inputs = {
  bucket_name = "orca-demo-dev-data"
  # acl, block_public_access, enable_encryption and enable_versioning are all
  # left at their secure defaults.
}
