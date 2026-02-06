variable "cluster_name" {
  description = "Cluster name for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for security group ingress (PostgreSQL access from VPC only)"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for RDS (private subnets, 3 AZs)"
  type        = list(string)
}

variable "availability_zones" {
  description = "Availability zones for the cluster (1 writer + 2 readers across 3 AZs)"
  type        = list(string)
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.12"
}

variable "instance_class" {
  description = "DB cluster instance class (e.g. db.m6gd.large, db.r6gd.large)"
  type        = string
  default     = "db.m6gd.large"
}

variable "allocated_storage" {
  description = "Allocated storage in GB per instance"
  type        = number
  default     = 100
}

variable "storage_type" {
  description = "Storage type for Multi-AZ DB cluster (io1 or io2)"
  type        = string
  default     = "io1"
}

variable "iops" {
  description = "Provisioned IOPS for Multi-AZ DB cluster"
  type        = number
  default     = 1000
}

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
