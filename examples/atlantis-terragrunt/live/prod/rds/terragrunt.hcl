# prod: second demo unit, showing the same pattern on a database and adding a
# secret. `atlantis plan` on this unit should fail the Orca gate.

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/examples/atlantis-terragrunt/modules//rds"
}

inputs = {
  identifier = "orca-demo-prod-db"
  vpc_id     = "vpc-0a1b2c3d4e5f67890"

  # IaC finding: database reachable from the internet.
  publicly_accessible = true

  # IaC finding: storage not encrypted at rest.
  storage_encrypted = false

  # IaC finding: database port open to the world.
  allowed_cidr_blocks = ["0.0.0.0/0"]

  # Secrets finding: master password as a literal in version control. This is a
  # made-up string, not a real credential — it is here so the demo shows the
  # secrets scan and the IaC scan hitting the same file. In practice this input
  # should come from a secrets manager, e.g.
  #   master_password = get_env("TF_VAR_db_password")
  master_password = "Pr0d-Dem0-N0tR3al-9f2c"

  # IaC finding: backups effectively disabled.
  backup_retention_period = 0
}
