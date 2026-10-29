################################################################################
# Common (same names on the AWS, GCP and Azure modules)
################################################################################

variable "name" {
  description = "Prefix for every resource the module creates. Lowercase letters, digits and hyphens, at most 20 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", var.name))
    error_message = "name must be 3-20 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "domain" {
  description = "FQDN Plane is served on. It is also the licence domain and part of the instance identity, so it must never change after install."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", var.domain))
    error_message = "domain must be a lowercase FQDN, e.g. plane.example.com."
  }
}

variable "deployment_mode" {
  description = "How Plane runs. Only \"eks\" is available in this release; \"docker\" (one EC2 instance with prime-cli) comes in v0.2."
  type        = string
  default     = "eks"

  validation {
    condition     = contains(["eks"], var.deployment_mode)
    error_message = "Only deployment_mode = \"eks\" is supported in this release."
  }
}

variable "plane_version" {
  description = "Plane release to install (chart planeVersion)."
  type        = string
  default     = "v4.0.0"
}

variable "chart_version" {
  description = "plane-enterprise Helm chart version."
  type        = string
  default     = "3.11.1"
}

variable "acme_email" {
  description = "Let's Encrypt account email. Required when route53_zone_id is set (the module then issues the certificate itself)."
  type        = string
  default     = null
}

variable "acme_server" {
  description = "ACME directory URL. Use the Let's Encrypt staging URL for tests to avoid rate limits."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "allowed_cidrs" {
  description = "Source CIDRs allowed to reach Plane on 443/80 through the load balancer."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_components" {
  description = "Optional Plane workloads. pi (Plane AI) needs AI provider keys, which are set in the admin UI in this release."
  type = object({
    silo   = optional(bool, true)
    drawio = optional(bool, true)
    pi     = optional(bool, false)
  })
  default = {}
}

variable "tags" {
  description = "Tags applied to every AWS resource."
  type        = map(string)
  default     = {}
}

################################################################################
# DNS and TLS
################################################################################

variable "route53_zone_id" {
  description = <<-EOT
    Public Route 53 hosted zone that contains domain. When set, the module writes an alias record to the load balancer and issues the certificate
    (cert-manager, DNS-01). When null, DNS and the certificate are a manual step: see the README.
  EOT
  type        = string
  default     = null
}

variable "tls_secret_name" {
  description = "Kubernetes TLS Secret in the plane namespace that Traefik serves. Written by cert-manager when route53_zone_id is set; created by the operator otherwise."
  type        = string
  default     = "plane-tls"
}

################################################################################
# Network
################################################################################

variable "vpc_cidr" {
  description = "CIDR of the VPC the module creates. Must not overlap networks you will peer or VPN with. The default avoids 10.0.0.0/16, the default of most VPC tooling and of the older aws/terraform module."
  type        = string
  default     = "10.60.0.0/16"
}

variable "az_count" {
  description = "Availability zones to use. The RDS Multi-AZ DB cluster needs at least 3."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 3
    error_message = "az_count must be at least 3 (RDS Multi-AZ DB clusters need three AZs)."
  }
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cheaper, as today's module) instead of one per AZ."
  type        = bool
  default     = true
}

################################################################################
# EKS
################################################################################

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.36"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. The private endpoint is always on. Restrict this to your office, VPN or CI ranges."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_admin_principal_arns" {
  description = "IAM principal ARNs granted cluster-admin through EKS access entries. The identity running Terraform is added automatically."
  type        = list(string)
  default     = []
}

variable "node_group" {
  description = "The managed node group. Fixed size (no autoscaler in this release): change count and re-apply to scale."
  type = object({
    instance_types = optional(list(string), ["m7a.xlarge"])
    count          = optional(number, 2)
    disk_size_gb   = optional(number, 50)
  })
  default = {}
}

variable "addon_versions" {
  description = "EKS managed add-on versions. null for an add-on means the most recent version for kubernetes_version."
  type = object({
    vpc_cni                = optional(string, "v1.23.2-eksbuild.8")
    coredns                = optional(string, "v1.14.7-eksbuild.22")
    kube_proxy             = optional(string, "v1.36.0-eksbuild.58")
    eks_pod_identity_agent = optional(string, "v1.4.1-eksbuild.3")
    aws_ebs_csi_driver     = optional(string, "v1.67.2-eksbuild.1")
  })
  default = {}
}

variable "helm_timeout" {
  description = "Seconds to wait for the Plane Helm release. A fresh install's migrations take about 20 minutes."
  type        = number
  default     = 3600
}

variable "plane_values" {
  description = "Extra plane-enterprise chart values (YAML string), merged last. Never put secrets here: they end up in Terraform state and the Helm release."
  type        = string
  default     = ""
}

################################################################################
# Data services
################################################################################

variable "postgres" {
  description = "RDS PostgreSQL Multi-AZ DB cluster (1 writer + 2 readable standbys), sized as today's module."
  type = object({
    engine_version        = optional(string, "15.19")
    instance_class        = optional(string, "db.m6gd.large")
    allocated_storage_gb  = optional(number, 100)
    storage_type          = optional(string, "io1")
    iops                  = optional(number, 1000)
    backup_retention_days = optional(number, 14)
    deletion_protection   = optional(bool, true)
  })
  default = {}
}

variable "redis" {
  description = "ElastiCache Valkey with TLS, an AUTH token and at-rest encryption, as Plane's own production cache."
  type = object({
    engine_version = optional(string, "8.2")
    node_type      = optional(string, "cache.t3.medium")
    replicas       = optional(number, 0)
  })
  default = {}
}

variable "rabbitmq" {
  description = "Amazon MQ for RabbitMQ."
  type = object({
    engine_version  = optional(string, "3.13")
    instance_type   = optional(string, "mq.m7g.medium")
    deployment_mode = optional(string, "CLUSTER_MULTI_AZ")
  })
  default = {}

  validation {
    condition     = contains(["SINGLE_INSTANCE", "CLUSTER_MULTI_AZ"], var.rabbitmq.deployment_mode)
    error_message = "rabbitmq.deployment_mode must be SINGLE_INSTANCE or CLUSTER_MULTI_AZ."
  }
}

variable "bucket_force_destroy" {
  description = "Allow terraform destroy to delete the uploads bucket even when it holds objects."
  type        = bool
  default     = false
}
