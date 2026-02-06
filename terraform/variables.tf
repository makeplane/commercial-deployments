variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "plane-eks-cluster"

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
  default     = "1.34"
}

variable "eks" {
  description = "EKS node group configuration"
  type = object({
    node_instance_types = list(string)
    node_desired_size   = number
    node_min_size       = number
    node_max_size       = number
    node_disk_size      = number
    node_group_name     = string
    ssh_key_name        = string
  })
  default = {
    node_instance_types = ["m7a.xlarge"]
    node_desired_size   = 2
    node_min_size       = 2
    node_max_size       = 4
    node_disk_size      = 50
    node_group_name     = "default"
    ssh_key_name        = null
  }
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

variable "cache" {
  description = "ElastiCache Redis configuration"
  type = object({
    node_type      = string
    num_nodes      = number
    engine_version = string
  })
  default = {
    node_type      = "cache.t3.medium"
    num_nodes      = 1
    engine_version = "7.0"
  }
}

variable "opensearch" {
  description = "OpenSearch configuration"
  type = object({
    master_username = string
    engine_version  = string
    instance_type   = string
    instance_count  = number
    ebs_volume_size = number
  })
  default = {
    master_username = "admin"
    engine_version  = "OpenSearch_2.19"
    instance_type   = "r7g.large.search"
    instance_count  = 2
    ebs_volume_size = 10
  }
}

variable "object_store" {
  description = "S3 object store configuration"
  type = object({
    bucket_name_prefix  = string
    enable_versioning   = bool
    enable_vpc_endpoint = bool
  })
  default = {
    bucket_name_prefix  = "plane"
    enable_versioning   = false
    enable_vpc_endpoint = true
  }
}

variable "db" {
  description = "RDS PostgreSQL database configuration"
  type = object({
    name              = string
    username          = string
    engine_version    = string
    instance_class    = string
    allocated_storage = number
    storage_type      = string
    iops              = number
  })
  default = {
    name              = "plane"
    username          = "postgres"
    engine_version    = "15.12"
    instance_class    = "db.m6gd.large"
    allocated_storage = 100
    storage_type      = "io1"
    iops              = 1000
  }
}
