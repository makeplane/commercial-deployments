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
  nullable    = false

  validation {
    condition     = contains(["eks"], var.deployment_mode)
    error_message = "Only deployment_mode = \"eks\" is supported in this release."
  }
}

variable "plane_version" {
  description = "Plane release to install (chart planeVersion)."
  type        = string
  default     = "v4.0.1"
  nullable    = false
}

variable "chart_version" {
  description = "plane-enterprise Helm chart version. 3.11.3 or later (configurable email Service)."
  type        = string
  default     = "3.11.3"
  nullable    = false
}

variable "chart_repository" {
  description = "Helm repository of the plane-enterprise chart. Override only to test a preview build."
  type        = string
  default     = "https://helm.plane.so/"
  nullable    = false
}

variable "chart_name" {
  description = "Chart name in chart_repository (preview builds are named <commit>-plane-enterprise)."
  type        = string
  default     = "plane-enterprise"
  nullable    = false
}

variable "acme_email" {
  description = <<-EOT
    Let's Encrypt account email. When set, the module issues Plane's certificate with cert-manager: DNS-01 through
    Route 53 when route53_zone_id is set, otherwise HTTP-01 through Traefik (domain must already resolve to the load
    balancer, port 80 open). When null, provide the certificate yourself (tls_secret_name). Required with route53_zone_id.
  EOT
  type        = string
  default     = null
}

variable "acme_server" {
  description = "ACME directory URL. Use the Let's Encrypt staging URL for tests to avoid rate limits."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
  nullable    = false
}

variable "allowed_cidrs" {
  description = "Source CIDRs allowed to reach Plane on 443/80 through the load balancer."
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = false

  validation {
    condition     = var.acme_email == null || var.route53_zone_id != null || contains(var.allowed_cidrs, "0.0.0.0/0")
    error_message = "HTTP-01 (acme_email without route53_zone_id) needs allowed_cidrs to include 0.0.0.0/0: Let's Encrypt validates from the internet on port 80. Use a Route 53 zone (DNS-01) or your own certificate to restrict access."
  }
}

variable "enable_components" {
  description = "Optional Plane workloads. pi (Plane AI) needs AI provider keys, which are set in the admin UI in this release."
  type = object({
    silo   = optional(bool, true)
    drawio = optional(bool, true)
    pi     = optional(bool, false)
  })
  default  = {}
  nullable = false
}

variable "tags" {
  description = "Tags applied to every AWS resource."
  type        = map(string)
  default     = {}
  nullable    = false
}

################################################################################
# DNS and TLS
################################################################################

variable "route53_zone_id" {
  description = <<-EOT
    Public Route 53 hosted zone that contains domain. When set, the module writes an alias record to the load balancer
    and issues the certificate with DNS-01 (set acme_email). When null, you create the DNS record (CNAME to
    load_balancer_dns_name); the certificate then comes from HTTP-01 (acme_email) or from you. See the README.
  EOT
  type        = string
  default     = null
}

variable "tls_secret_name" {
  description = "Kubernetes TLS Secret in the plane namespace that Traefik serves. Written by cert-manager when acme_email is set; created by the operator otherwise."
  type        = string
  default     = "plane-tls"
  nullable    = false
}

################################################################################
# Network
################################################################################

variable "vpc_cidr" {
  description = "CIDR of the VPC the module creates. Must not overlap networks you will peer or VPN with. The default avoids 10.0.0.0/16, the default of most VPC tooling and of the older aws/terraform module."
  type        = string
  default     = "10.60.0.0/16"
  nullable    = false
}

variable "az_count" {
  description = "Availability zones to use. The RDS Multi-AZ DB cluster needs at least 3."
  type        = number
  default     = 3
  nullable    = false

  validation {
    condition     = var.az_count >= 3
    error_message = "az_count must be at least 3 (RDS Multi-AZ DB clusters need three AZs)."
  }
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cheaper, as today's module) instead of one per AZ."
  type        = bool
  default     = true
  nullable    = false
}

################################################################################
# EKS
################################################################################

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.36"
  nullable    = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. The private endpoint is always on. Restrict this to your office, VPN or CI ranges."
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = false
}

variable "cluster_admin_principal_arns" {
  description = "IAM principal ARNs granted cluster-admin through EKS access entries. The identity running Terraform is added automatically."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "node_group" {
  description = <<-EOT
    The managed node group: starts at desired_size nodes and can range from min_size to max_size (2 to 4 by default, as
    today). No node autoscaler in this release, so it stays at desired_size until scaled by hand (aws eks
    update-nodegroup-config --scaling-config desiredSize=N) or by an autoscaler added later. Terraform sets desired_size
    only at creation and leaves later changes alone.
  EOT
  type = object({
    instance_types = optional(list(string), ["m7a.xlarge"])
    min_size       = optional(number, 2)
    max_size       = optional(number, 4)
    desired_size   = optional(number, 2)
    disk_size_gb   = optional(number, 50)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.node_group.min_size >= 1 && var.node_group.min_size <= var.node_group.desired_size && var.node_group.desired_size <= var.node_group.max_size
    error_message = "node_group needs 1 <= min_size <= desired_size <= max_size."
  }
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
  default  = {}
  nullable = false
}

variable "helm_timeout" {
  description = "Seconds to wait for the Plane Helm release. A fresh install's migrations take about 20 minutes."
  type        = number
  default     = 3600
  nullable    = false
}

variable "plane_values" {
  description = "Extra plane-enterprise chart values (YAML string), merged last. Never put secrets here: they end up in Terraform state and the Helm release."
  type        = string
  default     = ""
  nullable    = false
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
  default  = {}
  nullable = false
}

variable "redis" {
  description = "ElastiCache Valkey with TLS, an AUTH token and at-rest encryption, as Plane's own production cache."
  type = object({
    engine_version = optional(string, "8.2")
    node_type      = optional(string, "cache.t3.medium")
    replicas       = optional(number, 0)
  })
  default  = {}
  nullable = false
}

variable "rabbitmq" {
  description = "Amazon MQ for RabbitMQ."
  type = object({
    engine_version  = optional(string, "3.13")
    instance_type   = optional(string, "mq.m7g.medium")
    deployment_mode = optional(string, "CLUSTER_MULTI_AZ")
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["SINGLE_INSTANCE", "CLUSTER_MULTI_AZ"], var.rabbitmq.deployment_mode)
    error_message = "rabbitmq.deployment_mode must be SINGLE_INSTANCE or CLUSTER_MULTI_AZ."
  }
}

variable "opensearch" {
  description = <<-EOT
    Amazon OpenSearch Service for Plane's search, on by default as in today's deployments: a private domain in the VPC
    (HTTPS only, KMS, node-to-node encryption), reached by Plane with its Pod Identity role (SigV4, no passwords). After
    the first install, create the search indexes once (see the README). enabled = false: Plane runs with search
    indexing off.
  EOT
  type = object({
    enabled        = optional(bool, true)
    engine_version = optional(string, "OpenSearch_2.19")
    instance_type  = optional(string, "r7g.large.search")
    instance_count = optional(number, 2)
    volume_size_gb = optional(number, 10)
    # Index names are "<index_prefix>_<name>", as today's deployments ("plane"). Changing it on a running install
    # needs the indexes created again and re-filled (manage_search_index index create + document index).
    index_prefix = optional(string, "plane")
  })
  default  = {}
  nullable = false
}

variable "email" {
  description = <<-EOT
    Plane's email service (inbound email to work items). On by default with its own internet-facing NLB (ports 25 SMTP,
    465 SMTPS, 587 submission), the sender's IP preserved. smtp_domain is the domain that receives mail (default
    "intake.<domain>"): point its MX record at the email_load_balancer_dns_name output (the module does it with
    route53_zone_id; the domain must then be in that zone). Certificate: Let's Encrypt DNS-01 with a Route 53 zone;
    otherwise the email app's own self-signed certificate. load_balancer = false keeps the service running with no load
    balancer (not reachable from the internet); enabled = false turns it off. Needs plane-enterprise chart 3.11.3+.
  EOT
  type = object({
    enabled       = optional(bool, true)
    smtp_domain   = optional(string)
    load_balancer = optional(bool, true)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.email.load_balancer || var.email.enabled
    error_message = "email.load_balancer needs email.enabled."
  }
}

variable "bucket_force_destroy" {
  description = "Allow terraform destroy to delete the uploads bucket even when it holds objects."
  type        = bool
  default     = false
  nullable    = false
}
