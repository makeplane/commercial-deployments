variable "name" {
  description = "Name prefix."
  type        = string
}

variable "domain" {
  description = "Plane FQDN (bucket CORS origin)."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the data services."
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "Security group allowed to reach PostgreSQL, Valkey and RabbitMQ (the EKS node SG). A single ID, not a set: it is unknown until apply."
  type        = string
}

variable "postgres" {
  description = "RDS Multi-AZ DB cluster settings."
  type = object({
    engine_version        = string
    instance_class        = string
    allocated_storage_gb  = number
    storage_type          = string
    iops                  = number
    backup_retention_days = number
    deletion_protection   = bool
  })
}

variable "redis" {
  description = "ElastiCache Valkey settings."
  type = object({
    engine_version = string
    node_type      = string
    replicas       = number
  })
}

variable "opensearch" {
  description = "Amazon OpenSearch Service settings."
  type = object({
    enabled        = bool
    engine_version = string
    instance_type  = string
    instance_count = number
    volume_size_gb = number
    index_prefix   = string
  })
}

variable "rabbitmq" {
  description = "Amazon MQ settings."
  type = object({
    engine_version  = string
    instance_type   = string
    deployment_mode = string
  })
}

variable "bucket_force_destroy" {
  description = "Let destroy delete a non-empty bucket."
  type        = bool
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}
