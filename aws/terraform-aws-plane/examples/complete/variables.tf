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
  description = "Public hosted zone containing domain. Leave null to create the DNS record yourself (CNAME to load_balancer_dns_name; see the module README)."
  type        = string
  default     = null
}

variable "acme_email" {
  description = "Let's Encrypt account email. Set it and the module issues the certificate (DNS-01 with route53_zone_id, HTTP-01 without)."
  type        = string
  default     = null
}

variable "acme_server" {
  description = "ACME directory. Set the Let's Encrypt staging URL for test installs."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "vpc_cidr" {
  description = "CIDR of the new VPC. Must not overlap networks you will peer or VPN with."
  type        = string
  default     = "10.60.0.0/16"
}

variable "admin_cidrs" {
  description = "CIDRs allowed to reach the EKS API (your office, VPN or CI)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "email_smtp_domain" {
  description = "Turn on Plane's email service (own NLB, ports 25/465/587) for this receiving domain. Null: email off."
  type        = string
  default     = null
}

variable "enable_opensearch" {
  description = "Create Amazon OpenSearch Service for Plane's search (2 x r7g.large.search). Off: Plane runs with search indexing off."
  type        = bool
  default     = false
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
