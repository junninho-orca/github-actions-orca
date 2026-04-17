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

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed SSH access"
  type        = string
}

resource "aws_s3_bucket" "demo_data" {
  bucket = "orca-demo-data-bucket"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "demo_data" {
  bucket = aws_s3_bucket.demo_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "demo_data" {
  bucket                  = aws_s3_bucket.demo_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_security_group" "web" {
  name        = "orca-demo-web"
  description = "Demo SG"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "demo" {
  identifier             = "orca-demo-db"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  username               = "admin"
  password               = var.db_password
  publicly_accessible    = false
  storage_encrypted      = true
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.web.id]
}
