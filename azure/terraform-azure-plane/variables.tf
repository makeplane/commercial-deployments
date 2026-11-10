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
  description = "How Plane runs. Only \"aks\" is available in this release."
  type        = string
  default     = "aks"
  nullable    = false

  validation {
    condition     = contains(["aks"], var.deployment_mode)
    error_message = "Only deployment_mode = \"aks\" is supported in this release."
  }
}

variable "plane_version" {
  description = "Plane release to install (chart planeVersion). Must include Plane's Azure Blob storage support (see README, \"Requires\"). Plane AI (enable_components.pi) needs the first release whose pi supports Azure Blob; the module checks it."
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
    error_message = "enable_components.pi needs plane_version ${local.pi_min_plane_version} or later (the first Plane release whose Plane AI supports Azure Blob storage)."
  }
}

variable "chart_version" {
  description = "plane-enterprise Helm chart version. Needs the bundled-RabbitMQ external secret (3.12.2) and the Azure Blob storage values (see README, \"Requires\")."
  type        = string
  default     = "3.12.2"
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
    Path A (ingress.mode = "automated"), variant A.1: the Let's Encrypt account email. cert-manager issues the web
    certificate with HTTP-01 through Traefik: Plane must be public on port 80, and the certificate is issued once your
    DNS record for domain points at load_balancer_ip. Leave null for your own certificate
    (ingress.tls_certificate_secret_id, variant A.2) or for path B.
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
  description = "Optional Plane workloads. pi (Plane AI) needs both pi.api_keys secrets, opensearch.enabled and a plane_version with Azure Blob support in Plane AI."
  type = object({
    silo   = optional(bool, true)
    drawio = optional(bool, true)
    pi     = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.enable_components.pi || var.opensearch.enabled
    error_message = "enable_components.pi needs opensearch.enabled: Plane AI creates its embedding model and indexes in the in-cluster OpenSearch."
  }
}

variable "pi" {
  description = <<-EOT
    Plane AI's models, used when enable_components.pi = true (needs OpenSearch). The module sets up semantic search
    (pi creates the embedding model in OpenSearch at startup) and a chat model. Chat (api_keys.chat_provider): a vendor
    key, "openai" (default), "anthropic", "xai", "baseten" or "meta", which gives Plane AI that vendor's models (it picks
    the default); or "custom": your own model on any OpenAI-compatible API (pi's custom LLM), and only that model.
    "custom" requires the OpenAI Chat Completions API at api_keys.chat_base_url (e.g. https://host/v1 serving
    /chat/completions, bearer key), such as Azure OpenAI's /openai/v1 endpoint, vLLM or LiteLLM; other APIs (such as
    Anthropic's native API) don't work. With "custom": chat_base_url and chat_model (required), chat_model_name
    (default chat_model) and chat_max_tokens (default 128000); set them only with "custom". Embeddings on Cohere
    (api_keys.embedding_model, cohere/embed-v4.0; or cohere/embed-english-v3.0, cohere/embed-english-v2.0). Both keys are required: each a Key Vault secret you create
    before the apply, given by its versionless resource ID, both in one RBAC vault in this subscription; plain text, or
    JSON with *_key_json_field naming the field (one JSON secret can hold both). The search indexes take the embedding
    model's dimension even with pi off, so choose the model before the first install, even if pi is enabled later:
    changing it later needs the search indexes recreated.
  EOT
  type = object({
    api_keys = optional(object({
      chat_provider       = optional(string, "openai")
      chat_key_secret_id  = optional(string)
      chat_key_json_field = optional(string)
      # chat_provider = "custom" only.
      chat_base_url            = optional(string)
      chat_model               = optional(string)
      chat_model_name          = optional(string)
      chat_max_tokens          = optional(number)
      embedding_model          = optional(string, "cohere/embed-v4.0")
      embedding_key_secret_id  = optional(string)
      embedding_key_json_field = optional(string)
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.enable_components.pi || (var.pi.api_keys.chat_key_secret_id != null && var.pi.api_keys.embedding_key_secret_id != null)
    error_message = "Plane AI needs both API keys: pi.api_keys.chat_key_secret_id and pi.api_keys.embedding_key_secret_id."
  }
  validation {
    condition     = contains(keys(local.pi_chat_key_envs), var.pi.api_keys.chat_provider)
    error_message = "pi.api_keys.chat_provider must be one of: ${join(", ", keys(local.pi_chat_key_envs))}."
  }
  validation {
    condition     = var.pi.api_keys.chat_provider != "custom" || can(regex("^https?://[^\\s/]+(/\\S*)?$", var.pi.api_keys.chat_base_url))
    error_message = "pi.api_keys.chat_base_url must be the base URL of an OpenAI-compatible API (OpenAI Chat Completions), e.g. \"https://my-llm.example.com/v1\"; chat_provider = \"custom\" requires it."
  }
  validation {
    condition     = var.pi.api_keys.chat_provider != "custom" || try(length(trimspace(var.pi.api_keys.chat_model)) > 0, false)
    error_message = "pi.api_keys.chat_provider = \"custom\" needs chat_model, the model ID that API expects (on Azure OpenAI, the deployment name)."
  }
  validation {
    condition     = var.pi.api_keys.chat_max_tokens == null || try(var.pi.api_keys.chat_max_tokens >= 1000 && floor(var.pi.api_keys.chat_max_tokens) == var.pi.api_keys.chat_max_tokens, false)
    error_message = "pi.api_keys.chat_max_tokens must be a whole number of at least 1000: the chat model's context window."
  }
  validation {
    condition = var.pi.api_keys.chat_provider == "custom" || alltrue([
      for v in [var.pi.api_keys.chat_base_url, var.pi.api_keys.chat_model, var.pi.api_keys.chat_model_name, var.pi.api_keys.chat_max_tokens] : v == null
    ])
    error_message = "pi.api_keys.chat_base_url, chat_model, chat_model_name and chat_max_tokens are only for chat_provider = \"custom\": a vendor key uses that vendor's API and models."
  }
  validation {
    condition = alltrue([
      for f in [var.pi.api_keys.chat_key_json_field, var.pi.api_keys.embedding_key_json_field] : f == null || can(regex("^\\S+$", f))
    ])
    error_message = "pi.api_keys.*_key_json_field must be the name of a field in the JSON secret (no spaces), or unset for a plain-text secret."
  }
  validation {
    condition     = contains(keys(local.pi_embedding_dimensions), var.pi.api_keys.embedding_model)
    error_message = "pi.api_keys.embedding_model must be a Cohere model: ${join(", ", keys(local.pi_embedding_dimensions))}."
  }
  validation {
    condition = alltrue([
      for id in [var.pi.api_keys.chat_key_secret_id, var.pi.api_keys.embedding_key_secret_id] :
      id == null || can(regex(local.key_vault_secret_regex, id))
    ])
    error_message = "pi.api_keys secret IDs must be ${local.key_vault_secret_format}."
  }
  validation {
    # One ExternalSecret reads through one SecretStore, and a SecretStore names one vault.
    condition = length(distinct([
      for id in compact([var.pi.api_keys.chat_key_secret_id, var.pi.api_keys.embedding_key_secret_id]) :
      lower(try(regex(local.key_vault_object_pattern, id).vault, id))
    ])) <= 1
    error_message = "pi.api_keys secrets must be in one Key Vault."
  }
}

variable "tags" {
  description = "Tags applied to every Azure resource."
  type        = map(string)
  default     = {}
  nullable    = false
}

################################################################################
# DNS and TLS
################################################################################

variable "ingress" {
  description = <<-EOT
    How traffic reaches Plane. mode = "automated" (path A): the module installs Traefik behind an Azure load balancer on
    a static IP, Plane's routes and the certificates (Let's Encrypt via acme_email, or your own via
    tls_certificate_secret_id). mode = "none" (path B, default): the module installs no ingress controller or routes; you
    bring your controller, routes, certificate and DNS after the apply. The module configures no DNS: the records are
    yours in both paths (see the dns_records output). Path A only: allowed_cidrs (who can reach Plane), scheme
    (internet-facing: a static public IP; internal: a fixed private IP in the AKS subnet; set at install, as changing it
    in place removes or adds the public IP while Traefik's load balancer still uses it: to switch, apply with
    mode = "none" first, see the README) and tls_certificate_secret_id (the versionless resource ID of a Key Vault certificate in this subscription, PEM or PFX, full chain:
    /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault>/certificates/<name>).
  EOT
  type = object({
    mode                      = optional(string, "none")
    allowed_cidrs             = optional(list(string), ["0.0.0.0/0"])
    scheme                    = optional(string, "internet-facing")
    tls_certificate_secret_id = optional(string)
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
    condition     = var.ingress.mode != "automated" || ((var.acme_email != null) != (var.ingress.tls_certificate_secret_id != null))
    error_message = "Path A (ingress.mode = \"automated\") needs exactly one web certificate source: acme_email (Let's Encrypt) or ingress.tls_certificate_secret_id (your own certificate)."
  }
  validation {
    condition     = !(var.ingress.mode == "automated" && var.acme_email != null) || (contains(var.ingress.allowed_cidrs, "0.0.0.0/0") && var.ingress.scheme == "internet-facing")
    error_message = "Let's Encrypt (acme_email) uses HTTP-01, which needs Plane reachable from the internet on port 80: ingress.allowed_cidrs must include 0.0.0.0/0 and ingress.scheme must be internet-facing. Use your own certificate (ingress.tls_certificate_secret_id) to restrict access."
  }
  validation {
    condition     = var.ingress.tls_certificate_secret_id == null || can(regex(local.key_vault_object_regex, var.ingress.tls_certificate_secret_id))
    error_message = "ingress.tls_certificate_secret_id must be ${local.key_vault_object_format}."
  }
}

variable "tls_secret_name" {
  description = "Path A: name of the Kubernetes TLS Secret in the plane namespace that Traefik serves. Written by cert-manager (acme_email) or by External Secrets from ingress.tls_certificate_secret_id."
  type        = string
  default     = "plane-tls"
  nullable    = false
}

variable "email" {
  description = <<-EOT
    Plane's email service (inbound email to work items). On by default with its own internet-facing Azure load balancer
    on a static public IP (ports 25 SMTP, 465 SMTPS, 587 submission), the sender's IP preserved. smtp_domain is the
    domain that receives mail (default "intake.<domain>"): create its A record pointing at email_load_balancer_ip and
    its MX record pointing at smtp_domain itself (see dns_records). Certificate: your own via certificate_secret_id (a
    Key Vault certificate, like ingress.tls_certificate_secret_id), else the email app's own self-signed certificate
    (fine for receiving mail). load_balancer = false keeps the service running with no load balancer (not reachable
    from the internet); enabled = false turns the service and its load balancer off. Needs plane-enterprise chart 3.11.3+.
  EOT
  type = object({
    enabled               = optional(bool, true)
    smtp_domain           = optional(string)
    load_balancer         = optional(bool, true)
    certificate_secret_id = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.email.certificate_secret_id == null || can(regex(local.key_vault_object_regex, var.email.certificate_secret_id))
    error_message = "email.certificate_secret_id must be ${local.key_vault_object_format}."
  }
}

################################################################################
# Azure: location and network
################################################################################

variable "location" {
  description = "Azure region, e.g. eastus2. It must offer availability zones, Azure Managed Redis, zone-redundant PostgreSQL HA and Premium ZRS disks."
  type        = string
}

variable "resource_group" {
  description = "Resource group for everything the module creates. create = true (default) creates \"<name>-rg\" (or name); create = false uses an existing, empty resource group."
  type = object({
    create = optional(bool, true)
    name   = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.resource_group.create || var.resource_group.name != null
    error_message = "resource_group.name is required when resource_group.create = false."
  }
}

variable "vnet_cidr" {
  description = "CIDR of the VNet the module creates (a /16 is expected): a /20 for the AKS nodes, a /24 delegated to PostgreSQL and a /24 for private endpoints. Must not overlap networks you will peer or VPN with, nor the pod (192.168.0.0/16) and service (172.16.0.0/16) ranges."
  type        = string
  default     = "10.60.0.0/16"
  nullable    = false

  validation {
    condition     = can(cidrhost(var.vnet_cidr, 0)) && tonumber(split("/", var.vnet_cidr)[1]) <= 16
    error_message = "vnet_cidr must be a valid CIDR of size /16 or larger."
  }
}

variable "zones" {
  description = "Availability zones for the nodes, the static IPs and PostgreSQL HA (primary in the first, standby in the second). Set at install: changing it replaces the static public IPs (new addresses), which fails while their load balancers use them."
  type        = list(string)
  default     = ["1", "2", "3"]
  nullable    = false

  validation {
    condition     = length(var.zones) >= 2
    error_message = "zones needs at least 2 zones (zone-redundant PostgreSQL HA)."
  }
}

################################################################################
# AKS
################################################################################

variable "kubernetes_version" {
  description = "AKS Kubernetes version (minor, e.g. \"1.35\"). AKS applies patch upgrades automatically."
  type        = string
  default     = "1.35"
  nullable    = false
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the public AKS API server. Empty (default) = open to all, as on AWS. Restrict this to your office, VPN or CI ranges; Terraform needs it during the apply."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "cluster_admin_object_ids" {
  description = "Entra ID object IDs (GUIDs of users, groups or service principals) granted \"Azure Kubernetes Service RBAC Cluster Admin\". The identity running Terraform is added automatically."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for id in var.cluster_admin_object_ids : can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", id))])
    error_message = "cluster_admin_object_ids must be Entra ID object IDs (GUIDs), not names or emails."
  }
}

variable "node_pool" {
  description = <<-EOT
    The AKS node pool (one pool, system mode, Azure Linux): starts at node_count nodes and the AKS cluster autoscaler
    keeps it between min_count and max_count (2 to 4 by default). Terraform sets node_count only at creation and
    leaves the autoscaler's changes alone. sku_tier is the AKS control-plane tier (Standard: uptime SLA).
  EOT
  type = object({
    vm_size         = optional(string, "Standard_D4ds_v5")
    min_count       = optional(number, 2)
    max_count       = optional(number, 4)
    node_count      = optional(number, 2)
    os_disk_size_gb = optional(number, 128)
    sku_tier        = optional(string, "Standard")
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.node_pool.min_count >= 1 && var.node_pool.min_count <= var.node_pool.node_count && var.node_pool.node_count <= var.node_pool.max_count
    error_message = "node_pool needs 1 <= min_count <= node_count <= max_count."
  }
  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.node_pool.sku_tier)
    error_message = "node_pool.sku_tier must be Free, Standard or Premium."
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
    Azure Database for PostgreSQL Flexible Server: VNet-integrated (no public access), TLS required, zone-redundant HA,
    databases plane and plane_pi. deletion_protection puts a CanNotDelete lock on the server: set it to false and apply
    before a destroy.
  EOT
  type = object({
    engine_version               = optional(string, "15")
    sku_name                     = optional(string, "GP_Standard_D2ds_v5")
    storage_mb                   = optional(number, 131072)
    high_availability_mode       = optional(string, "ZoneRedundant")
    backup_retention_days        = optional(number, 14)
    geo_redundant_backup_enabled = optional(bool, false)
    deletion_protection          = optional(bool, true)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["Disabled", "SameZone", "ZoneRedundant"], var.postgres.high_availability_mode)
    error_message = "postgres.high_availability_mode must be Disabled, SameZone or ZoneRedundant."
  }
  validation {
    condition     = var.postgres.backup_retention_days >= 7 && var.postgres.backup_retention_days <= 35
    error_message = "postgres.backup_retention_days must be between 7 and 35."
  }
}

variable "redis" {
  description = <<-EOT
    Azure Managed Redis: private endpoint only, TLS (port 10000), access-key auth (Plane's clients send a password only).
    persistence (default true) saves an RDB snapshot every 12 hours, the longest frequency Azure offers, and needs
    high_availability_enabled. Azure restores it to the same cache by itself after a failure: it isn't a backup you can
    download or import.
  EOT
  type = object({
    sku_name                  = optional(string, "Balanced_B3")
    high_availability_enabled = optional(bool, true)
    clustering_policy         = optional(string, "NoCluster")
    persistence               = optional(bool, true)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["NoCluster", "EnterpriseCluster"], var.redis.clustering_policy)
    error_message = "redis.clustering_policy must be NoCluster or EnterpriseCluster (Plane's Redis clients aren't cluster-aware)."
  }
  validation {
    condition     = !var.redis.persistence || var.redis.high_availability_enabled
    error_message = "redis.persistence needs redis.high_availability_enabled: Azure Managed Redis has no data persistence without high availability. Set persistence = false to turn high availability off."
  }
}

variable "rabbitmq" {
  description = "RabbitMQ. Azure has no managed AMQP 0-9-1 service, so it runs in the cluster from the chart (one node, a Premium ZRS disk of volume_size_gb), with its credentials from Key Vault. Set volume_size_gb before the first install: Kubernetes can't change it afterwards (to grow the disk, see the README)."
  type = object({
    volume_size_gb = optional(number, 10)
  })
  default  = {}
  nullable = false
}

variable "opensearch" {
  description = <<-EOT
    OpenSearch for Plane's search, on by default as on AWS. Azure has no managed OpenSearch, so it runs in the cluster
    from the chart (one node, a Premium ZRS disk of volume_size_gb), with its password from Key Vault. Set
    volume_size_gb before the first install: Kubernetes can't change it afterwards (to grow the disk, see the README).
    The chart's Job creates the search indexes after every install and upgrade. enabled = false: Plane runs with search
    indexing off.
  EOT
  type = object({
    enabled        = optional(bool, true)
    volume_size_gb = optional(number, 50)
    # Index names are "<index_prefix>_<name>", as today's deployments ("plane"). Changing it on a running install
    # needs the indexes created again and re-filled (manage_search_index index create + document index).
    index_prefix = optional(string, "plane")
  })
  default  = {}
  nullable = false
}

variable "storage" {
  description = <<-EOT
    Uploads storage: native Azure Blob Storage (needs Plane's Azure Blob support; see README, "Requires"). A StorageV2
    account with no shared keys (Entra ID only), reached through a private endpoint; Plane's pods use their workload
    identity, and browsers go through Plane's storage proxy (no SAS, no CORS). With versioning_enabled, previous blob
    versions are deleted 30 days after they were first written, counted from the original write. deletion_protection
    puts a CanNotDelete lock on the account: set it to false and apply before a destroy.
  EOT
  type = object({
    replication_type           = optional(string, "ZRS")
    container_name             = optional(string, "uploads")
    versioning_enabled         = optional(bool, true)
    soft_delete_retention_days = optional(number, 7)
    deletion_protection        = optional(bool, true)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.storage.replication_type)
    error_message = "storage.replication_type must be LRS, ZRS, GRS, GZRS, RAGRS or RAGZRS."
  }
  validation {
    condition     = var.storage.soft_delete_retention_days >= 1 && var.storage.soft_delete_retention_days <= 365
    error_message = "storage.soft_delete_retention_days must be between 1 and 365."
  }
}

variable "use_storage_proxy" {
  description = <<-EOT
    Whether uploads and downloads go through Plane. Azure supports only true: the storage account is private and the
    module uses no SAS or CORS, so every upload and download goes through Plane. Plane AI on Azure uses its own signed
    routes under /pi/. The chart and the api refuse false too. AWS and GCP expose the same input with a default of false.
  EOT
  type        = bool
  default     = true
  nullable    = false

  validation {
    condition     = var.use_storage_proxy
    error_message = "use_storage_proxy must be true on Azure: the storage account is private and the module uses no SAS or CORS, so every upload and download goes through Plane."
  }
}

variable "key_vault" {
  description = <<-EOT
    The Key Vault holding the generated secrets (RBAC mode). Its public endpoint stays on, gated by Entra ID RBAC;
    allowed_ips turns on its firewall (include the address Terraform runs from; the cluster's NAT IP is added
    automatically) and private_endpoint_enabled adds a private endpoint in the VNet. With purge protection (default), a
    destroyed vault stays soft-deleted for soft_delete_retention_days.
  EOT
  type = object({
    purge_protection_enabled   = optional(bool, true)
    soft_delete_retention_days = optional(number, 30)
    allowed_ips                = optional(list(string), [])
    private_endpoint_enabled   = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.key_vault.soft_delete_retention_days >= 7 && var.key_vault.soft_delete_retention_days <= 90
    error_message = "key_vault.soft_delete_retention_days must be between 7 and 90."
  }
}

variable "persistent_volume_sku" {
  description = "Azure disk SKU for the in-cluster RabbitMQ and OpenSearch volumes. Premium_ZRS lets their pods move to another zone. Set at install: changing it later needs the StatefulSets recreated."
  type        = string
  default     = "Premium_ZRS"
  nullable    = false

  validation {
    condition     = contains(["Premium_ZRS", "Premium_LRS", "StandardSSD_ZRS", "StandardSSD_LRS"], var.persistent_volume_sku)
    error_message = "persistent_volume_sku must be Premium_ZRS, Premium_LRS, StandardSSD_ZRS or StandardSSD_LRS."
  }
}
