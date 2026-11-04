# Every module input, same names and types; null means the module default. CI checks the names.

variable "name" {
  description = "Prefix for every resource the module creates. Lowercase letters, digits and hyphens, at most 20 characters."
  type        = string
}

variable "domain" {
  description = "FQDN Plane is served on. It is also the licence domain and part of the instance identity, so it must never change after install."
  type        = string
}

variable "deployment_mode" {
  description = "How Plane runs. Only \"gke\" is available in this release."
  type        = string
  default     = null
}

variable "plane_version" {
  description = "Plane release to install (chart planeVersion)."
  type        = string
  default     = null
}

variable "chart_version" {
  description = "plane-enterprise Helm chart version. 3.11.6 or later (the bundled RabbitMQ reads its credentials from an External Secrets Secret)."
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
    Path A (ingress.mode = "automated"), variant A.1: the Let's Encrypt account email. cert-manager issues the web
    certificate with HTTP-01 through Traefik: Plane must be public on port 80, and the certificate is issued once your
    DNS record for domain points at load_balancer_ip. Leave null for your own certificates
    (ingress.tls_certificate_secret, variant A.2) or for path B.
  EOT
  type        = string
  default     = null
}

variable "acme_server" {
  description = "ACME directory URL. Use the Let's Encrypt staging URL for tests to avoid rate limits."
  type        = string
  default     = null
}

variable "enable_components" {
  description = "Optional Plane workloads. pi (Plane AI) supports only S3 storage today, so it can't be turned on on GCP yet."
  type = object({
    silo   = optional(bool)
    drawio = optional(bool)
    pi     = optional(bool)
  })
  default = null
}

variable "labels" {
  description = "Labels applied to every GCP resource that supports them (GCP label rules: lowercase keys and values, digits, hyphens and underscores)."
  type        = map(string)
  default     = null
}

variable "ingress" {
  description = <<-EOT
    How traffic reaches Plane. mode = "automated" (path A): the module installs Traefik behind a GCP passthrough
    network load balancer on a reserved static IP, Plane's routes and the certificates (Let's Encrypt via acme_email, or
    your own via tls_certificate_secret). mode = "none" (path B, default): the module installs no ingress controller or
    routes; you bring your controller, routes, certificate and DNS after the apply. The module configures no DNS: the
    records are yours in both paths (see the dns_records output). Path A only: allowed_cidrs (who can reach Plane),
    scheme (internet-facing, or internal: an internal load balancer on an IP in the module's subnet; set at install, as
    changing it in place fails: to switch, apply with mode = "none" first, see the deployment guide) and
    tls_certificate_secret (a Secret Manager secret in project_id, as "projects/<project_id>/secrets/<name>", whose
    value is JSON with the keys "tls.crt" (full chain) and "tls.key").
  EOT
  type = object({
    mode                   = optional(string)
    allowed_cidrs          = optional(list(string))
    scheme                 = optional(string)
    tls_certificate_secret = optional(string)
  })
  default = null
}

variable "tls_secret_name" {
  description = "Path A: name of the Kubernetes TLS Secret in the plane namespace that Traefik serves. Written by cert-manager (acme_email) or by External Secrets from ingress.tls_certificate_secret."
  type        = string
  default     = null
}

variable "project_id" {
  description = "GCP project to deploy into (billing linked). Give Plane a project of its own: GKE admin roles are project-wide."
  type        = string
}

variable "region" {
  description = "GCP region for every regional resource (GKE, Cloud SQL, Memorystore, the bucket, the static IPs and the secrets' replicas)."
  type        = string
}

variable "zones" {
  description = "Zones of region for the GKE nodes. Empty (default): GKE picks three zones of the region."
  type        = list(string)
  default     = null
}

variable "enable_apis" {
  description = "Enable the project APIs the module needs (Compute, GKE, Service Networking, Cloud SQL Admin, Memorystore, Secret Manager, IAM, Cloud Storage). They are left on at destroy. Set false when your organisation enables APIs centrally."
  type        = bool
  default     = null
}

variable "network" {
  description = <<-EOT
    Address ranges of the VPC the module creates: subnet_cidr (nodes and internal load balancers), pods_cidr and
    services_cidr (the subnet's secondary ranges for GKE) and private_service_cidr (private services access, for Cloud
    SQL and Memorystore). They must not overlap each other or networks you will peer or VPN with. The defaults all sit
    in 10.60.0.0/15 and avoid 10.0.0.0/16.
  EOT
  type = object({
    subnet_cidr          = optional(string)
    services_cidr        = optional(string)
    private_service_cidr = optional(string)
    pods_cidr            = optional(string)
  })
  default = null
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the GKE API's public endpoint. Default open, as on AWS; restrict this to your office, VPN or CI ranges (Terraform needs it during the apply)."
  type        = list(string)
  default     = null
}

variable "cluster_admin_members" {
  description = "IAM members (user:…, group:…, serviceAccount:…) granted roles/container.admin on the project. The identity running Terraform needs it already."
  type        = list(string)
  default     = null
}

variable "release_channel" {
  description = "GKE release channel. GKE picks and upgrades the Kubernetes version within it."
  type        = string
  default     = null
}

variable "node_pool" {
  description = <<-EOT
    The GKE node pool, in every zone of the cluster (3 by default): min_per_zone to max_per_zone nodes per zone, scaled
    by the GKE cluster autoscaler (1-2 per zone, so 3-6 nodes). The third node, compared with AWS, carries the in-cluster
    OpenSearch and RabbitMQ. spot = true uses Spot VMs (cheaper, can be reclaimed: tests only).
  EOT
  type = object({
    machine_type = optional(string)
    min_per_zone = optional(number)
    max_per_zone = optional(number)
    disk_size_gb = optional(number)
    disk_type    = optional(string)
    spot         = optional(bool)
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
  description = <<-EOT
    Cloud SQL for PostgreSQL: private IP only, TLS required (ENCRYPTED_ONLY), regional high availability, backups with
    point-in-time recovery. The module creates the databases plane and plane_pi and the user plane (password generated,
    in Secret Manager). deletion_protection turns on both Terraform's and Cloud SQL's own protection.
  EOT
  type = object({
    database_version       = optional(string)
    tier                   = optional(string)
    edition                = optional(string)
    availability_type      = optional(string)
    disk_size_gb           = optional(number)
    disk_type              = optional(string)
    backup_retention_days  = optional(number)
    point_in_time_recovery = optional(bool)
    deletion_protection    = optional(bool)
  })
  default = null
}

variable "redis" {
  description = <<-EOT
    Memorystore for Redis, reached over private services access with an AUTH string (in Secret Manager). STANDARD_HA
    keeps a replica in another zone with automatic failover. transit_encryption (default true) turns on TLS (port 6378)
    with Memorystore's server CA trusted through the chart's customCA (every Plane service, plane-enterprise 3.11.6+);
    false keeps AUTH over the private network without TLS.
  EOT
  type = object({
    version            = optional(string)
    tier               = optional(string)
    memory_size_gb     = optional(number)
    transit_encryption = optional(bool)
  })
  default = null
}

variable "rabbitmq" {
  description = "RabbitMQ, run in the cluster by the chart (GCP has no managed RabbitMQ): one node on a persistent disk of volume_size_gb. Set the size before the first install: Kubernetes can't change it afterwards (to grow the disk, see the deployment guide). Its credentials are generated, stored in Secret Manager and synced by External Secrets."
  type = object({
    volume_size_gb = optional(number)
  })
  default = null
}

variable "opensearch" {
  description = <<-EOT
    OpenSearch for Plane's search, run in the cluster by the chart (GCP has no managed OpenSearch), on by default as in
    today's deployments: one node on a persistent disk of volume_size_gb, credentials generated, stored in Secret
    Manager and synced by External Secrets. Set volume_size_gb before the first install: Kubernetes can't change it
    afterwards (to grow the disk, see the deployment guide). The chart's Job creates the search indexes after every
    install and upgrade. enabled = false: Plane runs with search indexing off.
  EOT
  type = object({
    enabled        = optional(bool)
    volume_size_gb = optional(number)
    index_prefix   = optional(string)
  })
  default = null
}

variable "email" {
  description = <<-EOT
    Plane's email service (inbound email to work items). On by default with its own internet-facing passthrough load
    balancer on a reserved static IP (ports 25 SMTP, 465 SMTPS, 587 submission), the sender's IP preserved. smtp_domain is
    the domain that receives mail (default "intake.<domain>"): create an A record for it pointing at the
    email_load_balancer_ip output and an MX record naming it (see dns_records). Certificate: your own via
    certificate_secret (a Secret Manager secret like ingress.tls_certificate_secret), else the email app's own
    self-signed certificate (fine for receiving mail). load_balancer = false keeps the service running with no load
    balancer (not reachable from the internet); enabled = false turns the service and its load balancer off.
  EOT
  type = object({
    enabled            = optional(bool)
    smtp_domain        = optional(string)
    load_balancer      = optional(bool)
    certificate_secret = optional(string)
  })
  default = null
}

variable "use_storage_proxy" {
  description = "false (default): browsers upload and download directly from the bucket with signed URLs (the bucket allows CORS from domain). true: uploads and downloads go through Plane's api (no CORS needed, bounded by the ingress body limit)."
  type        = bool
  default     = null
}

variable "bucket_force_destroy" {
  description = "Allow terraform destroy to delete the uploads bucket even when it holds objects."
  type        = bool
  default     = null
}
