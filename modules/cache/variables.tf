variable "cluster_id" {
  description = "Cluster ID prefix for Redis"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for ElastiCache (private subnets)"
  type        = list(string)
}

variable "vpc_cidr" {
  description = "VPC CIDR block allowed to access Redis"
  type        = string
}

variable "node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "num_cache_clusters" {
  description = "Number of cache clusters (1 for single node, 2+ for replica)"
  type        = number
  default     = 1
}

variable "engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}

variable "port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
