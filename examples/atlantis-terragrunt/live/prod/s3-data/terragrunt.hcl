# prod: THE DEMO CASE.
#
# Read this file and then read modules/s3-bucket/main.tf. Neither one contains a
# public, unencrypted bucket. The bucket only becomes public and unencrypted
# once Terragrunt merges these inputs into that module — which is why a scanner
# pointed at .tf or .hcl files finds nothing here, and a scanner pointed at the
# rendered plan finds three findings.
#
# `atlantis plan` on this unit should fail the Orca gate.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/examples/atlantis-terragrunt/modules//s3-bucket"
}

inputs = {
  bucket_name = "orca-demo-prod-data"

  # IaC finding: public-read ACL on a bucket holding production data.
  acl = "public-read"

  # IaC finding: the public access block that would have neutered that ACL is
  # switched off. Two independently-safe defaults overridden together.
  block_public_access = false

  # IaC finding: no encryption at rest.
  enable_encryption = false

  # Not a finding on its own, but it removes the recovery path if the above is
  # exploited — worth pointing at during a walkthrough.
  enable_versioning = false
}
