############################################################
# A deliberately ordinary S3 module. There is nothing wrong
# with this file — its posture is decided entirely by the
# inputs Terragrunt passes in. See live/prod/s3-data.
############################################################

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    # ACLs are only honoured when the bucket owner does not take ownership of
    # every object, so a module that accepts an `acl` input needs this.
    object_ownership = var.acl == "private" ? "BucketOwnerEnforced" : "ObjectWriter"
  }
}

resource "aws_s3_bucket_acl" "this" {
  # BucketOwnerEnforced disallows ACLs entirely, so only attach one when the
  # caller actually asked for a non-private ACL.
  count = var.acl == "private" ? 0 : 1

  bucket     = aws_s3_bucket.this.id
  acl        = var.acl
  depends_on = [aws_s3_bucket_ownership_controls.this]
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  count = var.enable_encryption ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}
