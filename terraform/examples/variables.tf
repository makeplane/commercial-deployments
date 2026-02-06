variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
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
  description = "List of availability zones"
  type        = list(string)
  default     = null
}

variable "single_nat_gateway" {
  description = "Use single NAT gateway for cost optimization"
  type        = bool
  default     = true
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
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
    node_instance_types = ["t3.medium"]
    node_desired_size   = 3
    node_min_size       = 2
    node_max_size       = 10
    node_disk_size      = 50
    node_group_name     = "default"
    ssh_key_name        = null
  }
}

variable "tags" {
  description = "Additional tags"
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
    node_type      = "cache.t3.micro"
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
    engine_version  = "OpenSearch_2.11"
    instance_type   = "t3.small.search"
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
    bucket_name_prefix  = "app-data"
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
    name              = "appdb"
    username          = "postgres"
    engine_version    = "15.12"
    instance_class    = "db.m6gd.large"
    allocated_storage = 100
    storage_type      = "io1"
    iops              = 1000
  }
}
