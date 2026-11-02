variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Prefix for every resource the module creates (3-20 lowercase letters, digits and hyphens)."
  type        = string
}

variable "domain" {
  description = "FQDN Plane is served on. Never change it after install."
  type        = string
}

variable "acme_email" {
  description = "Let's Encrypt account email for the web certificate."
  type        = string
}

variable "compose_assets_url" {
  description = "Base URL of Plane's release assets (<url>/<version>/docker-compose.yml and variables.env); null for the module default."
  type        = string
  default     = null
}

variable "compose_assets_sha256" {
  description = "SHA-256 of docker-compose.yml and variables.env (recommended when compose_assets_url isn't Plane's)."
  type        = map(string)
  default     = null
}
