variable "bucket_name_prefix" {
  description = "Prefix for S3 bucket name (will append random suffix for uniqueness)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "route_table_ids" {
  description = "Route table IDs for S3 VPC endpoint (private route tables)"
  type        = list(string)
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = false
}

variable "enable_vpc_endpoint" {
  description = "Enable S3 gateway VPC endpoint for private access"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
