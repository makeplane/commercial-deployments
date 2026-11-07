# Mirrors the module's inputs (CI checks the names); null means the module default.

variable "subscription_id" {
  description = "Azure subscription to deploy into (null: ARM_SUBSCRIPTION_ID or the Azure CLI default)."
  type        = string
  default     = null
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
  description = "How Plane runs. Only \"aks\" is available in this release."
  type        = string
  default     = null
}

variable "plane_version" {
  description = "Plane release to install (chart planeVersion). Must include Plane's Azure Blob storage support (see README, \"Requires\")."
  type        = string
  default     = null
}

variable "chart_version" {
  description = "plane-enterprise Helm chart version. Needs the bundled-RabbitMQ external secret (3.12.2) and the Azure Blob storage values (see README, \"Requires\")."
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
    DNS record for domain points at load_balancer_ip. Leave null for your own certificate
    (ingress.tls_certificate_secret_id, variant A.2) or for path B.
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
  description = "Optional Plane workloads. pi (Plane AI) needs both pi.api_keys secrets, opensearch.enabled and a plane_version with Azure Blob support in Plane AI."
  type = object({
    silo   = optional(bool, true)
    drawio = optional(bool, true)
    pi     = optional(bool, false)
  })
  default = null
}

variable "pi" {
  description = "Plane AI's models (with enable_components.pi = true): OpenAI chat and Cohere embeddings by default, both keys required, each a plain-text secret in one Key Vault of yours, by versionless resource ID. The embedding model also sets the search indexes' dimension with pi off: choose it before the first install."
  type = object({
    api_keys = optional(object({
      chat_provider           = optional(string, "openai")
      chat_key_secret_id      = optional(string)
      embedding_model         = optional(string, "cohere/embed-v4.0")
      embedding_key_secret_id = optional(string)
    }), {})
  })
  default = null
}

variable "tags" {
  description = "Tags applied to every Azure resource."
  type        = map(string)
  default     = null
}

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
  default = null
}

variable "tls_secret_name" {
  description = "Path A: name of the Kubernetes TLS Secret in the plane namespace that Traefik serves. Written by cert-manager (acme_email) or by External Secrets from ingress.tls_certificate_secret_id."
  type        = string
  default     = null
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
  default = null
}

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
  default = null
}

variable "vnet_cidr" {
  description = "CIDR of the VNet the module creates (a /16 is expected): a /20 for the AKS nodes, a /24 delegated to PostgreSQL and a /24 for private endpoints. Must not overlap networks you will peer or VPN with, nor the pod (192.168.0.0/16) and service (172.16.0.0/16) ranges."
  type        = string
  default     = null
}

variable "zones" {
  description = "Availability zones for the nodes, the static IPs and PostgreSQL HA (primary in the first, standby in the second). Set at install: changing it replaces the static public IPs (new addresses), which fails while their load balancers use them."
  type        = list(string)
  default     = null
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version (minor, e.g. \"1.35\"). AKS applies patch upgrades automatically."
  type        = string
  default     = null
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the public AKS API server. Empty (default) = open to all, as on AWS. Restrict this to your office, VPN or CI ranges; Terraform needs it during the apply."
  type        = list(string)
  default     = null
}

variable "cluster_admin_object_ids" {
  description = "Entra ID object IDs (GUIDs of users, groups or service principals) granted \"Azure Kubernetes Service RBAC Cluster Admin\". The identity running Terraform is added automatically."
  type        = list(string)
  default     = null
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
  default = null
}

variable "redis" {
  description = "Azure Managed Redis: private endpoint only, TLS (port 10000), access-key auth (Plane's clients send a password only)."
  type = object({
    sku_name                  = optional(string, "Balanced_B1")
    high_availability_enabled = optional(bool, true)
    clustering_policy         = optional(string, "NoCluster")
  })
  default = null
}

variable "rabbitmq" {
  description = "RabbitMQ. Azure has no managed AMQP 0-9-1 service, so it runs in the cluster from the chart (one node, a Premium ZRS disk of volume_size_gb), with its credentials from Key Vault. Set volume_size_gb before the first install: Kubernetes can't change it afterwards (to grow the disk, see the README)."
  type = object({
    mode           = optional(string, "in-cluster")
    volume_size_gb = optional(number, 10)
  })
  default = null
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
    mode           = optional(string, "in-cluster")
    volume_size_gb = optional(number, 50)
    # Index names are "<index_prefix>_<name>", as today's deployments ("plane"). Changing it on a running install
    # needs the indexes created again and re-filled (manage_search_index index create + document index).
    index_prefix = optional(string, "plane")
  })
  default = null
}

variable "storage" {
  description = <<-EOT
    Uploads storage: native Azure Blob Storage (needs Plane's Azure Blob support; see README, "Requires"). A StorageV2
    account with no shared keys (Entra ID only), reached through a private endpoint; Plane's pods use their workload
    identity, and browsers go through Plane's storage proxy (no SAS, no CORS). deletion_protection puts a CanNotDelete
    lock on the account: set it to false and apply before a destroy.
  EOT
  type = object({
    replication_type           = optional(string, "ZRS")
    container_name             = optional(string, "uploads")
    versioning_enabled         = optional(bool, true)
    soft_delete_retention_days = optional(number, 7)
    deletion_protection        = optional(bool, true)
  })
  default = null
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
  default = null
}

variable "persistent_volume_sku" {
  description = "Azure disk SKU for the in-cluster RabbitMQ and OpenSearch volumes. Premium_ZRS lets their pods move to another zone. Set at install: changing it later needs the StatefulSets recreated."
  type        = string
  default     = null
}
