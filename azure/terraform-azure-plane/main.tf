data "azurerm_client_config" "current" {}

locals {
  # Path A: the module installs Traefik, Plane's routes and the certificates. Path B: none of them.
  automated    = var.ingress.mode == "automated"
  lets_encrypt = local.automated && var.acme_email != null
  internal     = var.ingress.scheme == "internal"

  # A subdomain, so its MX and A records never collide with domain's.
  email = merge(var.email, {
    smtp_domain   = coalesce(var.email.smtp_domain, "intake.${var.domain}")
    load_balancer = var.email.enabled && var.email.load_balancer
  })

  # Read from the resource/data source, not the input, so every module waits for the resource group.
  resource_group_name = var.resource_group.create ? azurerm_resource_group.this[0].name : data.azurerm_resource_group.this[0].name
  resource_group_id   = var.resource_group.create ? azurerm_resource_group.this[0].id : data.azurerm_resource_group.this[0].id

  # For 10.60.0.0/16: AKS nodes 10.60.0.0/20, PostgreSQL 10.60.16.0/24, private endpoints 10.60.17.0/24.
  aks_subnet_cidr               = cidrsubnet(var.vnet_cidr, 4, 0)
  postgres_subnet_cidr          = cidrsubnet(var.vnet_cidr, 8, 16)
  private_endpoints_subnet_cidr = cidrsubnet(var.vnet_cidr, 8, 17)

  # CNI Overlay: pods and Services take no VNet addresses.
  pod_cidr       = "192.168.0.0/16"
  service_cidr   = "172.16.0.0/16"
  dns_service_ip = "172.16.0.10"

  # Near the end of the AKS subnet (nodes fill from the start), so it's known before the apply.
  internal_ingress_ip = cidrhost(local.aks_subnet_cidr, -10)

  # Placeholder until the Plane release carrying pi Azure Blob support is known: it keeps pi refused until then.
  pi_min_plane_version = "v99.0.0"

  # Plane AI's Cohere and OpenAI embedding models (pi/core/embedding_config.py) and their vector dimensions.
  pi_embedding_dimensions = {
    "cohere/embed-v4.0"             = 1536
    "cohere/embed-english-v3.0"     = 1024
    "cohere/embed-english-v2.0"     = 4096
    "openai/text-embedding-ada-002" = 1536
    "openai/text-embedding-3-small" = 1536
    "openai/text-embedding-3-large" = 3072
  }
  # The api sizes its search indexes with this too, so it follows the model whether pi is on or off.
  pi_embedding_dimension = local.pi_embedding_dimensions[var.pi.api_keys.embedding_model]

  # The env var pi reads each key from => the secret holding it.
  pi_api_key_ids = var.enable_components.pi ? merge(
    { "${var.pi.api_keys.chat_provider == "anthropic" ? "CLAUDE" : "OPENAI"}_API_KEY" = var.pi.api_keys.chat_key_secret_id },
    { "${upper(split("/", var.pi.api_keys.embedding_model)[0])}_API_KEY" = var.pi.api_keys.embedding_key_secret_id },
  ) : {}
  pi_api_keys = { for env, id in local.pi_api_key_ids : env => local.customer_secrets[id] if id != null }

  # External Secrets reads each certificate's backing secret, which holds the private key.
  certificate_ids = {
    web  = local.automated ? var.ingress.tls_certificate_secret_id : null
    mail = local.email.enabled ? local.email.certificate_secret_id : null
  }
  certificates = { for k, id in local.certificate_ids : k => local.customer_secrets[id] if id != null }

  # Every Key Vault object of the customer's that External Secrets may read, by the ID given.
  customer_secrets = {
    for id in distinct(compact(concat(values(local.certificate_ids), values(local.pi_api_key_ids)))) : id => {
      vault = lower(regex(local.key_vault_object_pattern, id).vault)
      name  = regex(local.key_vault_object_pattern, id).name
      secret_scope = format(
        "/subscriptions/%s/resourceGroups/%s/providers/Microsoft.KeyVault/vaults/%s/secrets/%s",
        regex(local.key_vault_object_pattern, id).subscription,
        regex(local.key_vault_object_pattern, id).resource_group,
        regex(local.key_vault_object_pattern, id).vault,
        regex(local.key_vault_object_pattern, id).name,
      )
    }
  }
  key_vault_object_pattern = "(?i)^/subscriptions/(?P<subscription>[^/]+)/resourceGroups/(?P<resource_group>[^/]+)/providers/Microsoft\\.KeyVault/vaults/(?P<vault>[^/]+)/(?:certificates|secrets)/(?P<name>[^/]+)$"

  # Validates customer certificate IDs: versionless (External Secrets is granted that exact secret) and
  # in this subscription. "secrets/<name>" is accepted too.
  subscription_id         = data.azurerm_client_config.current.subscription_id
  key_vault_object_regex  = "(?i)^/subscriptions/${local.subscription_id}/resourceGroups/[-\\w.()]{0,89}[-\\w()]/providers/Microsoft\\.KeyVault/vaults/[a-z][a-z0-9-]{1,22}[a-z0-9]/(certificates|secrets)/[a-z0-9-]{1,127}$"
  key_vault_object_format = "the versionless resource ID of a Key Vault certificate in this subscription: /subscriptions/${local.subscription_id}/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault>/certificates/<name>"
  # Plane AI's keys are plain secrets, not certificates.
  key_vault_secret_regex  = replace(local.key_vault_object_regex, "(certificates|secrets)", "secrets")
  key_vault_secret_format = "the versionless resource ID of a Key Vault secret in this subscription: /subscriptions/${local.subscription_id}/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault>/secrets/<name>"

  # Azure tag names can't contain "/".
  tags = merge(var.tags, {
    "plane-deployment" = var.name
    "managed-by"       = "terraform-azure-plane"
  })
}

resource "azurerm_resource_group" "this" {
  count = var.resource_group.create ? 1 : 0

  name     = coalesce(var.resource_group.name, "${var.name}-rg")
  location = var.location

  tags = local.tags
}

data "azurerm_resource_group" "this" {
  count = var.resource_group.create ? 0 : 1

  name = var.resource_group.name
}

module "network" {
  source = "./modules/network"

  name                          = var.name
  location                      = var.location
  resource_group_name           = local.resource_group_name
  vnet_cidr                     = var.vnet_cidr
  aks_subnet_cidr               = local.aks_subnet_cidr
  postgres_subnet_cidr          = local.postgres_subnet_cidr
  private_endpoints_subnet_cidr = local.private_endpoints_subnet_cidr
  zones                         = var.zones
  tags                          = local.tags
}

# Static IPs exist before the cluster, so dns_records is complete after the first plan.
module "edge" {
  source = "./modules/edge"

  name                = var.name
  location            = var.location
  resource_group_name = local.resource_group_name
  zones               = var.zones
  ingress_public_ip   = local.automated && !local.internal
  email_public_ip     = local.email.load_balancer
  tags                = local.tags
}

module "cluster" {
  source = "./modules/cluster"

  name                            = var.name
  location                        = var.location
  resource_group_name             = local.resource_group_name
  resource_group_id               = local.resource_group_id
  subnet_id                       = module.network.aks_subnet_id
  zones                           = var.zones
  kubernetes_version              = var.kubernetes_version
  api_server_authorized_ip_ranges = var.api_server_authorized_ip_ranges
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  deployer_object_id              = data.azurerm_client_config.current.object_id
  cluster_admin_object_ids        = var.cluster_admin_object_ids
  node_pool                       = var.node_pool
  pod_cidr                        = local.pod_cidr
  service_cidr                    = local.service_cidr
  dns_service_ip                  = local.dns_service_ip
  tags                            = local.tags

  # On destroy the IPs must outlive the cluster (PublicIPAddressInUse). The cluster module has no
  # data sources, so this depends_on defers nothing at plan time.
  depends_on = [module.edge]
}

module "data" {
  source = "./modules/data"

  name                        = var.name
  location                    = var.location
  resource_group_name         = local.resource_group_name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  deployer_object_id          = data.azurerm_client_config.current.object_id
  vnet_id                     = module.network.vnet_id
  postgres_subnet_id          = module.network.postgres_subnet_id
  private_endpoints_subnet_id = module.network.private_endpoints_subnet_id
  nat_public_ip               = module.network.nat_public_ip
  zones                       = var.zones
  postgres                    = var.postgres
  redis                       = var.redis
  opensearch_enabled          = var.opensearch.enabled
  storage                     = var.storage
  key_vault                   = var.key_vault
  tags                        = local.tags
}

module "addons" {
  source = "./modules/addons"

  name                   = var.name
  location               = var.location
  resource_group_name    = local.resource_group_name
  tenant_id              = data.azurerm_client_config.current.tenant_id
  oidc_issuer_url        = module.cluster.oidc_issuer_url
  install_traefik        = local.automated
  allowed_cidrs          = var.ingress.allowed_cidrs
  load_balancer_scheme   = var.ingress.scheme
  ingress_public_ip_name = module.edge.ingress_public_ip_name
  internal_ingress_ip    = local.internal_ingress_ip
  issue_certificate      = local.lets_encrypt
  key_vault_id           = module.data.key_vault_id
  customer_secret_scopes = distinct([for s in values(local.customer_secrets) : s.secret_scope])
  tags                   = local.tags

  # A signal, not depends_on: a module-level depends_on would defer every data source inside it.
  cluster_ready = module.cluster.ready
}

module "plane" {
  source = "./modules/plane"

  name                 = var.name
  location             = var.location
  resource_group_name  = local.resource_group_name
  tenant_id            = data.azurerm_client_config.current.tenant_id
  oidc_issuer_url      = module.cluster.oidc_issuer_url
  domain               = var.domain
  plane_version        = var.plane_version
  chart_version        = var.chart_version
  pod_cidr             = local.pod_cidr
  enable_components    = var.enable_components
  tls_secret_name      = var.tls_secret_name
  email                = local.email
  email_public_ip_name = module.edge.email_public_ip_name
  chart_repository     = var.chart_repository
  chart_name           = var.chart_name
  ingress_enabled      = local.automated
  acme_email           = local.lets_encrypt ? var.acme_email : null
  acme_server          = var.acme_server
  certificates         = local.certificates
  pi = {
    embedding_model     = var.pi.api_keys.embedding_model
    embedding_dimension = local.pi_embedding_dimension
    api_keys_vault      = one(distinct([for k in values(local.pi_api_keys) : k.vault]))
    api_key_names       = { for env, k in local.pi_api_keys : env => k.name }
  }
  rabbitmq              = var.rabbitmq
  opensearch            = var.opensearch
  persistent_volume_sku = var.persistent_volume_sku
  helm_timeout          = var.helm_timeout
  plane_values          = var.plane_values
  data                  = module.data.plane_inputs
  tags                  = local.tags

  # extraObjects need the add-ons' CRDs and webhooks; on destroy, Plane goes first.
  addons_ready = module.addons.ready
}

# A warning, not an error: the email app self-signs, which is fine for receiving mail.
check "email_certificate" {
  assert {
    condition     = !local.automated || !local.email.enabled || !local.email.load_balancer || local.email.certificate_secret_id != null
    error_message = "No email certificate (email.certificate_secret_id): the email service uses a self-signed one. That's fine for receiving mail; import a certificate into Key Vault and set email.certificate_secret_id for a trusted one."
  }
}
