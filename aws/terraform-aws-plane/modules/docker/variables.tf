variable "name" {
  description = "Name prefix."
  type        = string
}

variable "domain" {
  description = "FQDN Plane is served on."
  type        = string
}

variable "plane_version" {
  description = "Plane release (compose asset version and image tag)."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR (path B: where the customer's load balancer connects from)."
  type        = string
}

variable "subnet_id" {
  description = "Subnet for the instance: a public subnet for path A internet-facing, else a private one."
  type        = string
}

variable "availability_zone" {
  description = "AZ of subnet_id (the data volume must be in the same AZ)."
  type        = string
}

variable "ingress" {
  description = "Root ingress input with mode resolved (automated = path A, none = path B)."
  type = object({
    mode                       = string
    allowed_cidrs              = list(string)
    scheme                     = string
    tls_certificate_secret_arn = optional(string)
  })
}

variable "acme_email" {
  description = "Let's Encrypt account email (path A.1), else null."
  type        = string
  default     = null
}

variable "acme_server" {
  description = "ACME directory URL."
  type        = string
}

variable "email" {
  description = "Root email input with smtp_domain resolved."
  type = object({
    enabled                = bool
    smtp_domain            = string
    load_balancer          = bool
    certificate_secret_arn = optional(string)
  })
}

variable "enable_components" {
  description = "Optional Plane workloads (drawio has no Compose service and is ignored)."
  type = object({
    silo   = bool
    drawio = bool
    pi     = bool
  })
}

variable "docker" {
  description = "Root docker input."
  type = object({
    instance_type           = string
    data_services           = string
    root_volume_gb          = number
    data_volume_gb          = number
    data_volume_snapshot_id = optional(string)
    compose_assets_url      = string
    compose_assets_sha256   = map(string)
    docker_version          = string
    compose_version         = string
    extra_env               = map(string)
    backup_time             = string
    backup_retention_days   = number
    setup_timeout_minutes   = number
  })
}

variable "bucket_force_destroy" {
  description = "Allow destroy to delete the backups bucket with objects in it."
  type        = bool
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}
