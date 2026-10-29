variable "name" {
  description = "Name prefix."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "domain" {
  description = "Plane FQDN."
  type        = string
}

variable "plane_version" {
  description = "Plane release (chart planeVersion)."
  type        = string
}

variable "chart_version" {
  description = "plane-enterprise chart version."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR (trusted proxy range for the api)."
  type        = string
}

variable "enable_components" {
  description = "Optional Plane workloads."
  type = object({
    silo   = bool
    drawio = bool
    pi     = bool
  })
}

variable "tls_secret_name" {
  description = "TLS Secret Traefik serves."
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 zone for DNS-01 (null = HTTP-01 when acme_email is set)."
  type        = string
}

variable "email" {
  description = "Plane's email service: on, the domain that receives mail, and whether it gets its own NLB."
  type = object({
    enabled       = bool
    smtp_domain   = string
    load_balancer = bool
  })
}

variable "public_subnet_ids" {
  description = "Public subnets for the email NLB."
  type        = list(string)
}

variable "chart_repository" {
  description = "Helm repository of the plane-enterprise chart."
  type        = string
}

variable "chart_name" {
  description = "Chart name in that repository."
  type        = string
}

variable "acme_email" {
  description = "Let's Encrypt account email (null = manual certificate)."
  type        = string
}

variable "acme_server" {
  description = "ACME directory URL."
  type        = string
}

variable "helm_timeout" {
  description = "Seconds to wait for the release."
  type        = number
}

variable "plane_values" {
  description = "Extra chart values (YAML), merged last."
  type        = string
}

variable "data" {
  description = "Data-layer endpoints and secret ARNs (modules/data plane_inputs)."
  type = object({
    kms_key_arn         = string
    bucket_name         = string
    bucket_arn          = string
    postgres_host       = string
    postgres_port       = number
    postgres_db         = string
    postgres_secret_arn = string
    redis_host          = string
    redis_port          = number
    redis_secret_arn    = string
    rabbitmq_host       = string
    rabbitmq_port       = number
    rabbitmq_secret_arn = string
    app_keys_secret_arn = string

    opensearch_enabled     = bool
    opensearch_endpoint    = string
    opensearch_domain_name = string
    opensearch_domain_arn  = string
    opensearch_prefix      = string
  })
}

variable "addons_ready" {
  description = "Readiness signal from the addons module. Gates the Plane release (and orders its destroy first)."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}
