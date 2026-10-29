# Every module input, same names and types. Unset (null) means the module default: set only what you need in
# terraform.tfvars (see terraform.tfvars.example for every default). Generated to match the module; CI checks the names.

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Prefix for every resource the module creates. Lowercase letters, digits and hyphens, at most 20 characters."
  type        = string

}

variable "domain" {
  description = "FQDN Plane is served on. It is also the licence domain and part of the instance identity, so it must never change after install."
  type        = string

}

variable "deployment_mode" {
  description = "How Plane runs. Only \"eks\" is available in this release; \"docker\" (one EC2 instance with prime-cli) comes in v0.2."
  type        = string
  default     = null
}

variable "plane_version" {
  description = "Plane release to install (chart planeVersion)."
  type        = string
  default     = null
}

variable "chart_version" {
  description = "plane-enterprise Helm chart version. 3.11.3 or later (configurable email Service)."
  type        = string
  default     = null
}

variable "chart_repository" {
  description = "Helm repository of the plane-enterprise chart. Override only to test a preview build."
  type        = string
  default     = null
}

variable "chart_name" {
  description = "Chart name in chart_repository (preview builds are named <commit>-plane-enterprise)."
  type        = string
  default     = null
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
  default     = null
}

variable "allowed_cidrs" {
  description = "Source CIDRs allowed to reach Plane on 443/80 through the load balancer."
  type        = list(string)
  default     = null
}

variable "enable_components" {
  description = "Optional Plane workloads. pi (Plane AI) needs AI provider keys, which are set in the admin UI in this release."
  type = object({
    silo   = optional(bool)
    drawio = optional(bool)
    pi     = optional(bool)
  })
  default = null
}

variable "tags" {
  description = "Tags applied to every AWS resource."
  type        = map(string)
  default     = null
}

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
  default     = null
}

variable "vpc_cidr" {
  description = "CIDR of the VPC the module creates. Must not overlap networks you will peer or VPN with. The default avoids 10.0.0.0/16, the default of most VPC tooling and of the older aws/terraform module."
  type        = string
  default     = null
}

variable "az_count" {
  description = "Availability zones to use. The RDS Multi-AZ DB cluster needs at least 3."
  type        = number
  default     = null
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cheaper, as today's module) instead of one per AZ."
  type        = bool
  default     = null
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = null
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. The private endpoint is always on. Restrict this to your office, VPN or CI ranges."
  type        = list(string)
  default     = null
}

variable "cluster_admin_principal_arns" {
  description = "IAM principal ARNs granted cluster-admin through EKS access entries. The identity running Terraform is added automatically."
  type        = list(string)
  default     = null
}

variable "node_group" {
  description = <<-EOT
    The managed node group: starts at desired_size nodes and can range from min_size to max_size (2 to 4 by default, as
    today). No node autoscaler in this release, so it stays at desired_size until scaled by hand (aws eks
    update-nodegroup-config --scaling-config desiredSize=N) or by an autoscaler added later. Terraform sets desired_size
    only at creation and leaves later changes alone.
  EOT
  type = object({
    instance_types = optional(list(string))
    min_size       = optional(number)
    max_size       = optional(number)
    desired_size   = optional(number)
    disk_size_gb   = optional(number)
  })
  default = null
}

variable "addon_versions" {
  description = "EKS managed add-on versions. null for an add-on means the most recent version for kubernetes_version."
  type = object({
    vpc_cni                = optional(string)
    coredns                = optional(string)
    kube_proxy             = optional(string)
    eks_pod_identity_agent = optional(string)
    aws_ebs_csi_driver     = optional(string)
  })
  default = null
}

variable "helm_timeout" {
  description = "Seconds to wait for the Plane Helm release. A fresh install's migrations take about 20 minutes."
  type        = number
  default     = null
}

variable "plane_values" {
  description = "Extra plane-enterprise chart values (YAML string), merged last. Never put secrets here: they end up in Terraform state and the Helm release."
  type        = string
  default     = null
}

variable "postgres" {
  description = "RDS PostgreSQL Multi-AZ DB cluster (1 writer + 2 readable standbys), sized as today's module."
  type = object({
    engine_version        = optional(string)
    instance_class        = optional(string)
    allocated_storage_gb  = optional(number)
    storage_type          = optional(string)
    iops                  = optional(number)
    backup_retention_days = optional(number)
    deletion_protection   = optional(bool)
  })
  default = null
}

variable "redis" {
  description = "ElastiCache Valkey with TLS, an AUTH token and at-rest encryption, as Plane's own production cache."
  type = object({
    engine_version = optional(string)
    node_type      = optional(string)
    replicas       = optional(number)
  })
  default = null
}

variable "rabbitmq" {
  description = "Amazon MQ for RabbitMQ."
  type = object({
    engine_version  = optional(string)
    instance_type   = optional(string)
    deployment_mode = optional(string)
  })
  default = null
}

variable "opensearch" {
  description = <<-EOT
    Amazon OpenSearch Service for Plane's search, on by default as in today's deployments: a private domain in the VPC
    (HTTPS only, KMS, node-to-node encryption), reached by Plane with its Pod Identity role (SigV4, no passwords). After
    the first install, create the search indexes once (see the README). enabled = false: Plane runs with search
    indexing off.
  EOT
  type = object({
    enabled        = optional(bool)
    engine_version = optional(string)
    instance_type  = optional(string)
    instance_count = optional(number)
    volume_size_gb = optional(number)
    index_prefix   = optional(string)
  })
  default = null
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
    enabled       = optional(bool)
    smtp_domain   = optional(string)
    load_balancer = optional(bool)
  })
  default = null
}

variable "bucket_force_destroy" {
  description = "Allow terraform destroy to delete the uploads bucket even when it holds objects."
  type        = bool
  default     = null
}
