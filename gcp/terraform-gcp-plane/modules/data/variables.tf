variable "name" {
  description = "Name prefix."
  type        = string
}

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
}

variable "domain" {
  description = "Plane FQDN (bucket CORS origin)."
  type        = string
}

variable "network_id" {
  description = "VPC network ID (private services access)."
  type        = string
}

variable "private_service_range" {
  description = "Name of the private services access range. Available once the peering exists."
  type        = string
}

variable "postgres" {
  description = "Cloud SQL settings."
  type = object({
    database_version            = string
    tier                        = string
    edition                     = string
    availability_type           = string
    disk_size_gb                = number
    disk_type                   = string
    backup_retention_days       = number
    point_in_time_recovery      = bool
    deletion_protection         = bool
    final_backup                = bool
    final_backup_retention_days = number
  })
}

variable "redis" {
  description = "Memorystore for Redis settings."
  type = object({
    version             = string
    tier                = string
    memory_size_gb      = number
    persistence         = bool
    rdb_snapshot_period = string
  })
}

variable "opensearch" {
  description = "In-cluster OpenSearch settings (only enabled is read here)."
  type = object({
    enabled        = bool
    volume_size_gb = number
    index_prefix   = string
  })
}

variable "bucket_force_destroy" {
  description = "Let destroy delete a non-empty bucket."
  type        = bool
}

variable "labels" {
  description = "Labels."
  type        = map(string)
}
