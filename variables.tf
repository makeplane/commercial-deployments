variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string

  validation {
    condition     = length(var.cluster_name) >= 1 && length(var.cluster_name) <= 100
    error_message = "Cluster name must be between 1 and 100 characters."
  }
}

variable "region" {
  description = "AWS region for resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones (defaults to 2 in the specified region)"
  type        = list(string)
  default     = null
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway for cost optimization (vs one per AZ)"
  type        = bool
  default     = true
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.28"
}

variable "node_instance_types" {
  description = "List of instance types for the node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of nodes in the node group"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes in the node group"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes in the node group"
  type        = number
  default     = 5
}

variable "node_disk_size" {
  description = "Disk size in GiB for worker nodes"
  type        = number
  default     = 50
}

variable "node_group_name" {
  description = "Name of the managed node group"
  type        = string
  default     = "default"
}

variable "ssh_key_name" {
  description = "SSH key name for EC2 instances (optional)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

# MQ (Amazon MQ RabbitMQ)
variable "mq_username" {
  description = "RabbitMQ username"
  type        = string
  default     = "admin"
}

variable "mq_engine_version" {
  description = "RabbitMQ engine version (valid: 4.2, 3.13)"
  type        = string
  default     = "4.2"
}

variable "mq_instance_type" {
  description = "MQ broker instance type"
  type        = string
  default     = "mq.t3.micro"
}

variable "mq_deployment_mode" {
  description = "MQ deployment mode: SINGLE_INSTANCE, ACTIVE_STANDBY_MULTI_AZ, or CLUSTER_MULTI_AZ"
  type        = string
  default     = "SINGLE_INSTANCE"
}

# Cache (ElastiCache Redis)
variable "cache_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "cache_num_nodes" {
  description = "Number of Redis cache nodes (1 for single, 2+ for replica)"
  type        = number
  default     = 1
}

variable "cache_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}

# OpenSearch
variable "opensearch_master_username" {
  description = "OpenSearch master username for fine-grained access control"
  type        = string
  default     = "admin"
}

variable "opensearch_engine_version" {
  description = "OpenSearch engine version"
  type        = string
  default     = "OpenSearch_2.11"
}

variable "opensearch_instance_type" {
  description = "OpenSearch instance type"
  type        = string
  default     = "t3.small.search"
}

variable "opensearch_instance_count" {
  description = "Number of OpenSearch instances"
  type        = number
  default     = 2
}

variable "opensearch_ebs_volume_size" {
  description = "OpenSearch EBS volume size in GB"
  type        = number
  default     = 10
}

# Object Store (S3)
variable "bucket_name_prefix" {
  description = "Prefix for S3 bucket name"
  type        = string
  default     = "app-data"
}

variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = false
}

variable "enable_s3_vpc_endpoint" {
  description = "Enable S3 gateway VPC endpoint for private access"
  type        = bool
  default     = true
}

# Database (RDS Multi-AZ DB Cluster - PostgreSQL)
variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "plane"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "postgres"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.12"
}

variable "db_instance_class" {
  description = "DB cluster instance class (e.g. db.m6gd.large)"
  type        = string
  default     = "db.m6gd.large"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB per instance"
  type        = number
  default     = 100
}

variable "db_storage_type" {
  description = "Storage type for Multi-AZ DB cluster (io1 or io2)"
  type        = string
  default     = "io1"
}

variable "db_iops" {
  description = "Provisioned IOPS for Multi-AZ DB cluster"
  type        = number
  default     = 1000
}
