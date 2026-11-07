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
  description = "How Plane runs. Only \"gke\" is available in this release."
  type        = string
  default     = "gke"
  nullable    = false

  validation {
    condition     = contains(["gke"], var.deployment_mode)
    error_message = "Only deployment_mode = \"gke\" is supported in this release."
  }
}

variable "plane_version" {
  description = "Plane release to install (chart planeVersion). Plane AI (enable_components.pi) needs the first release whose pi supports GCS storage; the module checks it."
  type        = string
  default     = "v4.0.1"
  nullable    = false

  validation {
    # Releases (vX.Y.Z) compared as one number; other tags (preview or on-demand builds) aren't checked.
    condition = !var.enable_components.pi || try(
      sum([for i, n in regex("^v?([0-9]+)\\.([0-9]+)\\.([0-9]+)", var.plane_version) : tonumber(n) * pow(1000, 2 - i)]) >=
      sum([for i, n in regex("^v?([0-9]+)\\.([0-9]+)\\.([0-9]+)", local.pi_min_plane_version) : tonumber(n) * pow(1000, 2 - i)]),
      true
    )
    error_message = "enable_components.pi needs plane_version ${local.pi_min_plane_version} or later (the first Plane release whose Plane AI supports GCS storage)."
  }
}

variable "chart_version" {
  description = "plane-enterprise Helm chart version. 3.12.2 or later (the bundled RabbitMQ reads its credentials from an External Secrets Secret, and the OpenSearch heap Plane AI needs can be set)."
  type        = string
  # 3.12.2 is pending release (helm-charts#370); earlier charts refuse to render this module's values.
  default  = "3.12.2"
  nullable = false
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
  default     = "https://acme-v02.api.letsencrypt.org/directory"
  nullable    = false
}

variable "enable_components" {
  description = "Optional Plane workloads. pi (Plane AI) needs both pi.api_keys secrets, opensearch.enabled and a plane_version with GCS support in Plane AI."
  type = object({
    silo   = optional(bool, true)
    drawio = optional(bool, true)
    pi     = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.enable_components.pi || var.opensearch.enabled
    error_message = "enable_components.pi needs opensearch.enabled = true: Plane AI keeps its search and embeddings in OpenSearch."
  }
}

variable "pi" {
  description = <<-EOT
    Plane AI's models, used when enable_components.pi = true (needs OpenSearch). The module sets up semantic search
    (pi creates the embedding model in OpenSearch at startup) and a chat model: chat on OpenAI (api_keys.chat_provider;
    or Anthropic) and embeddings on Cohere (api_keys.embedding_model, cohere/embed-v4.0; or another Cohere or OpenAI
    model: cohere/embed-english-v3.0, cohere/embed-english-v2.0, openai/text-embedding-ada-002,
    openai/text-embedding-3-small, openai/text-embedding-3-large). Both API keys are required: each is a plain-text
    Secret Manager secret in project_id, as "projects/<project_id>/secrets/<name>" (one secret for both when OpenAI does
    chat and embeddings). The search indexes take the embedding model's dimension even with pi off, so choose the model
    before the first install, even if pi is enabled later: changing it later needs the search indexes recreated.
  EOT
  type = object({
    api_keys = optional(object({
      chat_provider        = optional(string, "openai")
      chat_key_secret      = optional(string)
      embedding_model      = optional(string, "cohere/embed-v4.0")
      embedding_key_secret = optional(string)
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.enable_components.pi || (var.pi.api_keys.chat_key_secret != null && var.pi.api_keys.embedding_key_secret != null)
    error_message = "Plane AI needs both API keys: pi.api_keys.chat_key_secret and pi.api_keys.embedding_key_secret."
  }
  validation {
    condition     = contains(["openai", "anthropic"], var.pi.api_keys.chat_provider)
    error_message = "pi.api_keys.chat_provider must be \"openai\" or \"anthropic\"."
  }
  validation {
    condition     = contains(keys(local.pi_embedding_dimensions), var.pi.api_keys.embedding_model)
    error_message = "pi.api_keys.embedding_model must be a Cohere or OpenAI model: ${join(", ", keys(local.pi_embedding_dimensions))}."
  }
  validation {
    condition = alltrue([
      for s in [var.pi.api_keys.chat_key_secret, var.pi.api_keys.embedding_key_secret] :
      s == null || can(regex("^projects/${var.project_id}/secrets/[A-Za-z0-9_-]{1,255}$", s))
    ])
    error_message = "pi.api_keys secrets must be Secret Manager secrets in project_id, as \"projects/<project_id>/secrets/<name>\"."
  }
  validation {
    condition     = !(var.pi.api_keys.chat_provider == "openai" && startswith(var.pi.api_keys.embedding_model, "openai/")) || var.pi.api_keys.chat_key_secret == var.pi.api_keys.embedding_key_secret
    error_message = "OpenAI for both chat and embeddings uses one key (OPENAI_API_KEY): set the same secret for both."
  }
}

variable "labels" {
  description = "Labels applied to every GCP resource that supports them (GCP label rules: lowercase keys and values, digits, hyphens and underscores)."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "labels keys must start with a lowercase letter; keys and values may use lowercase letters, digits, hyphens and underscores (at most 63 characters)."
  }
}

################################################################################
# DNS and TLS
################################################################################

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
    mode                   = optional(string, "none")
    allowed_cidrs          = optional(list(string), ["0.0.0.0/0"])
    scheme                 = optional(string, "internet-facing")
    tls_certificate_secret = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["none", "automated"], var.ingress.mode)
    error_message = "ingress.mode must be \"automated\" (path A) or \"none\" (path B)."
  }
  validation {
    condition     = contains(["internet-facing", "internal"], var.ingress.scheme)
    error_message = "ingress.scheme must be \"internet-facing\" or \"internal\"."
  }
  validation {
    condition     = var.ingress.mode != "automated" || ((var.acme_email != null) != (var.ingress.tls_certificate_secret != null))
    error_message = "Path A (ingress.mode = \"automated\") needs exactly one web certificate source: acme_email (Let's Encrypt) or ingress.tls_certificate_secret (your own certificate)."
  }
  validation {
    condition     = !(var.ingress.mode == "automated" && var.acme_email != null) || (contains(var.ingress.allowed_cidrs, "0.0.0.0/0") && var.ingress.scheme == "internet-facing")
    error_message = "Let's Encrypt (acme_email) uses HTTP-01, which needs Plane reachable from the internet on port 80: ingress.allowed_cidrs must include 0.0.0.0/0 and ingress.scheme must be internet-facing. Use your own certificate (ingress.tls_certificate_secret) to restrict access."
  }
  validation {
    condition     = var.ingress.tls_certificate_secret == null || can(regex("^projects/${var.project_id}/secrets/[A-Za-z0-9_-]{1,255}$", var.ingress.tls_certificate_secret))
    error_message = "ingress.tls_certificate_secret must be a Secret Manager secret in project_id, as \"projects/<project_id>/secrets/<name>\"."
  }
}

variable "tls_secret_name" {
  description = "Path A: name of the Kubernetes TLS Secret in the plane namespace that Traefik serves. Written by cert-manager (acme_email) or by External Secrets from ingress.tls_certificate_secret."
  type        = string
  default     = "plane-tls"
  nullable    = false
}

################################################################################
# GCP project and network
################################################################################

variable "project_id" {
  description = "GCP project to deploy into (billing linked). Give Plane a project of its own: GKE admin roles are project-wide."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a GCP project ID (6-30 characters: lowercase letters, digits and hyphens)."
  }
}

variable "region" {
  description = "GCP region for every regional resource (GKE, Cloud SQL, Memorystore, the bucket, the static IPs and the secrets' replicas)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a GCP region, e.g. us-central1."
  }
}

variable "zones" {
  description = "Zones of region for the GKE nodes. Empty (default): GKE picks three zones of the region."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for z in var.zones : startswith(z, "${var.region}-")])
    error_message = "Every zone must be in region (e.g. us-central1-a for region us-central1)."
  }
}

variable "enable_apis" {
  description = "Enable the project APIs the module needs (Compute, GKE, Service Networking, Cloud SQL Admin, Memorystore, Secret Manager, IAM, Cloud Storage). They are left on at destroy. Set false when your organisation enables APIs centrally."
  type        = bool
  default     = true
  nullable    = false
}

variable "network" {
  description = <<-EOT
    Address ranges of the VPC the module creates: subnet_cidr (nodes and internal load balancers), pods_cidr and
    services_cidr (the subnet's secondary ranges for GKE) and private_service_cidr (private services access, for Cloud
    SQL and Memorystore). They must not overlap each other or networks you will peer or VPN with. The defaults all sit
    in 10.60.0.0/15 and avoid 10.0.0.0/16.
  EOT
  type = object({
    subnet_cidr          = optional(string, "10.60.0.0/20")
    services_cidr        = optional(string, "10.60.16.0/20")
    private_service_cidr = optional(string, "10.60.32.0/20")
    pods_cidr            = optional(string, "10.61.0.0/16")
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for c in [var.network.subnet_cidr, var.network.services_cidr, var.network.private_service_cidr, var.network.pods_cidr] :
      can(cidrhost(c, 0)) && cidrhost(c, 0) == split("/", c)[0]
    ])
    error_message = "Every network range must be a valid CIDR whose address is the start of the range (e.g. 10.60.0.0/20)."
  }
  validation {
    condition     = tonumber(split("/", var.network.private_service_cidr)[1]) <= 24
    error_message = "network.private_service_cidr must be /24 or larger (Cloud SQL and Memorystore each take ranges from it); /20 is recommended."
  }
}

################################################################################
# GKE
################################################################################

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the GKE API's public endpoint. Default open, as on AWS; restrict this to your office, VPN or CI ranges (Terraform needs it during the apply)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = false

  validation {
    condition     = length(var.master_authorized_networks) > 0 && alltrue([for c in var.master_authorized_networks : can(cidrhost(c, 0))])
    error_message = "master_authorized_networks must list at least one valid CIDR."
  }
}

variable "cluster_admin_members" {
  description = "IAM members (user:…, group:…, serviceAccount:…) granted roles/container.admin on the project. The identity running Terraform needs it already."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for m in var.cluster_admin_members : can(regex("^(user|group|serviceAccount|domain|principal|principalSet):.+", m))])
    error_message = "cluster_admin_members entries must be IAM members such as user:alice@example.com or group:platform@example.com."
  }
}

variable "release_channel" {
  description = "GKE release channel. GKE picks and upgrades the Kubernetes version within it."
  type        = string
  default     = "REGULAR"
  nullable    = false

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
}

variable "node_pool" {
  description = <<-EOT
    The GKE node pool, in every zone of the cluster (3 by default): min_per_zone to max_per_zone nodes per zone, scaled
    by the GKE cluster autoscaler (1-2 per zone, so 3-6 nodes). The third node, compared with AWS, carries the in-cluster
    OpenSearch and RabbitMQ. spot = true uses Spot VMs (cheaper, can be reclaimed: tests only).
  EOT
  type = object({
    machine_type = optional(string, "n2d-standard-4")
    min_per_zone = optional(number, 1)
    max_per_zone = optional(number, 2)
    disk_size_gb = optional(number, 50)
    disk_type    = optional(string, "pd-balanced")
    spot         = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.node_pool.min_per_zone >= 1 && var.node_pool.min_per_zone <= var.node_pool.max_per_zone
    error_message = "node_pool needs 1 <= min_per_zone <= max_per_zone."
  }
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
  description = <<-EOT
    Cloud SQL for PostgreSQL: private IP only, TLS required (ENCRYPTED_ONLY), regional high availability, backups with
    point-in-time recovery. The module creates the databases plane and plane_pi and the user plane (password generated,
    in Secret Manager). deletion_protection turns on both Terraform's and Cloud SQL's own protection. final_backup: Cloud
    SQL takes a last backup when the instance is deleted and keeps it for final_backup_retention_days (1-365), after
    terraform destroy; automated backups are deleted with the instance. Changing it restarts the instance.
  EOT
  type = object({
    database_version            = optional(string, "POSTGRES_15")
    tier                        = optional(string, "db-custom-2-8192")
    edition                     = optional(string, "ENTERPRISE")
    availability_type           = optional(string, "REGIONAL")
    disk_size_gb                = optional(number, 100)
    disk_type                   = optional(string, "PD_SSD")
    backup_retention_days       = optional(number, 14)
    point_in_time_recovery      = optional(bool, true)
    deletion_protection         = optional(bool, true)
    final_backup                = optional(bool, true)
    final_backup_retention_days = optional(number, 30)
  })
  default  = {}
  nullable = false

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.postgres.database_version))
    error_message = "postgres.database_version must be a Cloud SQL PostgreSQL version such as POSTGRES_15."
  }
  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.postgres.availability_type)
    error_message = "postgres.availability_type must be REGIONAL (high availability) or ZONAL."
  }
  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.postgres.edition)
    error_message = "postgres.edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
  validation {
    condition     = var.postgres.final_backup_retention_days >= 1 && var.postgres.final_backup_retention_days <= 365
    error_message = "postgres.final_backup_retention_days must be between 1 and 365."
  }
}

variable "redis" {
  description = <<-EOT
    Memorystore for Redis, reached over private services access with an AUTH string (in Secret Manager). STANDARD_HA
    keeps a replica in another zone with automatic failover. transit_encryption (default true) turns on TLS (port 6378)
    with Memorystore's server CA trusted through the chart's customCA (every Plane service, plane-enterprise 3.12.2+);
    false keeps AUTH over the private network without TLS. persistence (default true) takes an RDB snapshot every
    rdb_snapshot_period (ONE_HOUR, SIX_HOURS, TWELVE_HOURS or TWENTY_FOUR_HOURS), on every tier: STANDARD_HA restores from
    the replica first and the snapshot only if that fails; BASIC restores from the snapshot after a restart.
  EOT
  type = object({
    version             = optional(string, "REDIS_7_2")
    tier                = optional(string, "STANDARD_HA")
    memory_size_gb      = optional(number, 4)
    transit_encryption  = optional(bool, true)
    persistence         = optional(bool, true)
    rdb_snapshot_period = optional(string, "TWENTY_FOUR_HOURS")
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["BASIC", "STANDARD_HA"], var.redis.tier)
    error_message = "redis.tier must be BASIC or STANDARD_HA."
  }
  validation {
    condition     = contains(["ONE_HOUR", "SIX_HOURS", "TWELVE_HOURS", "TWENTY_FOUR_HOURS"], var.redis.rdb_snapshot_period)
    error_message = "redis.rdb_snapshot_period must be ONE_HOUR, SIX_HOURS, TWELVE_HOURS or TWENTY_FOUR_HOURS."
  }
}

variable "rabbitmq" {
  description = "RabbitMQ, run in the cluster by the chart (GCP has no managed RabbitMQ): one node on a persistent disk of volume_size_gb. Set the size before the first install: Kubernetes can't change it afterwards (to grow the disk, see the deployment guide). Its credentials are generated, stored in Secret Manager and synced by External Secrets."
  type = object({
    volume_size_gb = optional(number, 10)
  })
  default  = {}
  nullable = false
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
    enabled        = optional(bool, true)
    volume_size_gb = optional(number, 20)
    # Index names are "<index_prefix>_<name>", as today's deployments ("plane"). Changing it on a running install
    # needs the indexes created again and re-filled (manage_search_index index create + document index).
    index_prefix = optional(string, "plane")
  })
  default  = {}
  nullable = false
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
    enabled            = optional(bool, true)
    smtp_domain        = optional(string)
    load_balancer      = optional(bool, true)
    certificate_secret = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.email.certificate_secret == null || can(regex("^projects/${var.project_id}/secrets/[A-Za-z0-9_-]{1,255}$", var.email.certificate_secret))
    error_message = "email.certificate_secret must be a Secret Manager secret in project_id, as \"projects/<project_id>/secrets/<name>\"."
  }
}

variable "use_storage_proxy" {
  description = "false (default): browsers upload and download directly from the bucket with signed URLs (the bucket allows CORS from domain). true: uploads and downloads go through Plane's api (no CORS needed, bounded by the ingress body limit)."
  type        = bool
  default     = false
  nullable    = false
}

variable "bucket_force_destroy" {
  description = "Allow terraform destroy to delete the uploads bucket even when it holds objects."
  type        = bool
  default     = false
  nullable    = false
}
