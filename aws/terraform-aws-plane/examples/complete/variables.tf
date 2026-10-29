variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "plane"
}

variable "domain" {
  description = "FQDN Plane is served on. Never change it after install."
  type        = string
}

variable "route53_zone_id" {
  description = "Public hosted zone containing domain. Leave null to create DNS and the certificate by hand (see the module README)."
  type        = string
  default     = null
}

variable "acme_email" {
  description = "Let's Encrypt account email (needed with route53_zone_id)."
  type        = string
  default     = null
}

variable "acme_server" {
  description = "ACME directory. Set the Let's Encrypt staging URL for test installs."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "admin_cidrs" {
  description = "CIDRs allowed to reach the EKS API (your office, VPN or CI)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "postgres_deletion_protection" {
  description = "Block deletion of the database. Set false only for test installs you plan to destroy."
  type        = bool
  default     = true
}

variable "bucket_force_destroy" {
  description = "Let terraform destroy delete the uploads bucket even when it holds files. Test installs only."
  type        = bool
  default     = false
}

variable "cluster_admin_principal_arns" {
  description = "Extra IAM principals granted cluster-admin."
  type        = list(string)
  default     = []
}
