variable "name" {
  description = "Name prefix."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group (Plane's identity; the email public IP)."
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant (SecretStores)."
  type        = string
}

variable "oidc_issuer_url" {
  description = "The cluster's OIDC issuer (Workload Identity)."
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

variable "pod_cidr" {
  description = "Pod CIDR (trusted proxy range for the api: Traefik's pods)."
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

variable "ingress_enabled" {
  description = "Path A: render Plane's Traefik routes (and issue or sync the web certificate)."
  type        = bool
}

variable "certificates" {
  description = "Customer certificates in Key Vault, by role (web: path A; mail): vault name, certificate name and the backing secret's ID."
  type = map(object({
    vault        = string
    name         = string
    secret_scope = string
  }))
}

variable "email" {
  description = "Plane's email service: on, the domain that receives mail, and whether it gets its own load balancer."
  type = object({
    enabled               = bool
    smtp_domain           = string
    load_balancer         = bool
    certificate_secret_id = string
  })
}

variable "email_public_ip_name" {
  description = "Name of the email service's static public IP (null without the load balancer)."
  type        = string
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

variable "rabbitmq" {
  description = "In-cluster RabbitMQ settings."
  type = object({
    mode           = string
    volume_size_gb = number
  })
}

variable "opensearch" {
  description = "In-cluster OpenSearch settings."
  type = object({
    enabled        = bool
    mode           = string
    volume_size_gb = number
    index_prefix   = string
  })
}

variable "persistent_volume_sku" {
  description = "Azure disk SKU of the in-cluster services' volumes."
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
  description = "Data-layer endpoints and Key Vault secret names (modules/data plane_inputs)."
  type = object({
    key_vault_uri = string

    postgres_host        = string
    postgres_port        = number
    postgres_db          = string
    postgres_secret_name = string

    redis_host        = string
    redis_port        = number
    redis_secret_name = string

    rabbitmq_secret_name   = string
    opensearch_secret_name = string
    app_keys_secret_name   = string
    app_key_names          = list(string)

    storage_account_name   = string
    storage_container_name = string
    storage_container_id   = string
    storage_blob_endpoint  = string
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
