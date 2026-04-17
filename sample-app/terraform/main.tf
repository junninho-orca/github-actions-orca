############################################################
# Sample Terraform with intentional misconfigurations for the
# Orca IaC scan demo. Do NOT apply. For illustration only.
############################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# IaC finding: S3 bucket with public-read ACL and no encryption.
resource "aws_s3_bucket" "demo_data" {
  bucket = "orca-demo-data-bucket"
}

resource "aws_s3_bucket_acl" "demo_data" {
  bucket = aws_s3_bucket.demo_data.id
  acl    = "public-read"
}

# IaC finding: security group open to the world on SSH.
resource "aws_security_group" "web" {
  name        = "orca-demo-web"
  description = "Demo SG"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IaC finding: RDS instance with public access and no encryption at rest.
resource "aws_db_instance" "demo" {
  identifier             = "orca-demo-db"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  username               = "admin"
  password               = "ChangeMe123!" # also a secrets-scan finding
  publicly_accessible    = true
  storage_encrypted      = false
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.web.id]
}
