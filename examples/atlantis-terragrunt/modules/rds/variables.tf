# As with the s3-bucket module, every default here is the secure one.

variable "identifier" {
  description = "DB instance identifier."
  type        = string
}

variable "vpc_id" {
  description = "VPC the instance and its security group live in."
  type        = string
}

variable "master_username" {
  description = "Master username."
  type        = string
  default     = "appadmin"
}

variable "master_password" {
  description = "Master password. Should come from a secrets manager, never a literal."
  type        = string
  sensitive   = true
}

variable "publicly_accessible" {
  description = "Assign a public IP to the instance."
  type        = bool
  default     = false
}

variable "storage_encrypted" {
  description = "Encrypt storage at rest."
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDRs permitted to reach the database port."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "backup_retention_period" {
  description = "Days of automated backups to retain."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
