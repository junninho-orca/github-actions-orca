############################################################
# An ordinary Postgres module. Like the s3-bucket module, its
# posture comes entirely from the inputs it is given.
############################################################

resource "aws_security_group" "db" {
  name        = "${var.identifier}-db"
  description = "Database access for ${var.identifier}"
  vpc_id      = var.vpc_id
  tags        = var.tags

  ingress {
    description = "Postgres"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "this" {
  identifier     = var.identifier
  engine         = "postgres"
  engine_version = "16.4"
  instance_class = "db.t3.medium"

  allocated_storage = 50
  storage_encrypted = var.storage_encrypted

  username = var.master_username
  password = var.master_password

  publicly_accessible    = var.publicly_accessible
  vpc_security_group_ids = [aws_security_group.db.id]

  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = true

  tags = var.tags
}

output "endpoint" {
  value = aws_db_instance.this.endpoint
}
