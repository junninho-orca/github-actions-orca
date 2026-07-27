# Every security-relevant setting is an input, and every default is the SECURE
# one. That is deliberate: it means an insecure plan can only come from an
# environment's terragrunt.hcl overriding a default, which is exactly the class
# of problem that scanning module .tf files cannot see.

variable "bucket_name" {
  description = "Bucket name."
  type        = string
}

variable "acl" {
  description = "Canned ACL to apply to the bucket."
  type        = string
  default     = "private"
}

variable "block_public_access" {
  description = "Apply the account-level public access block to this bucket."
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable server-side encryption at rest."
  type        = bool
  default     = true
}

variable "enable_versioning" {
  description = "Enable object versioning."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
