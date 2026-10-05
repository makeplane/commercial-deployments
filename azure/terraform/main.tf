data "azurerm_client_config" "current" {}

locals {
  # Read back from the resource/data source (not the input) so every module
  # implicitly depends on the resource group existing.
  resource_group_name = var.create_resource_group ? azurerm_resource_group.main[0].name : data.azurerm_resource_group.main[0].name
  resource_group_id   = var.create_resource_group ? azurerm_resource_group.main[0].id : data.azurerm_resource_group.main[0].id

  # PostgreSQL and Redis hostnames are global, so their names carry a random suffix.
  unique_name = "${var.name}-${random_id.suffix.hex}"

  # For 10.0.0.0/16: aks = 10.0.0.0/20, postgres = 10.0.16.0/24, private endpoints = 10.0.17.0/24
  aks_subnet_cidr               = cidrsubnet(var.vnet_cidr, 4, 0)
  postgres_subnet_cidr          = cidrsubnet(var.vnet_cidr, 8, 16)
  private_endpoints_subnet_cidr = cidrsubnet(var.vnet_cidr, 8, 17)

  tags = merge({ deployed-by = "plane.so" }, var.tags)
}

resource "random_id" "suffix" {
  byte_length = 2
}

resource "azurerm_resource_group" "main" {
  count = var.create_resource_group ? 1 : 0

  name     = coalesce(var.resource_group_name, "${var.name}-rg")
  location = var.location

  tags = local.tags
}

data "azurerm_resource_group" "main" {
  count = var.create_resource_group ? 0 : 1

  name = coalesce(var.resource_group_name, "${var.name}-rg")
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

module "aks" {
  source = "./modules/aks"

  name                            = var.name
  location                        = var.location
  resource_group_name             = local.resource_group_name
  resource_group_id               = local.resource_group_id
  subnet_id                       = module.network.aks_subnet_id
  zones                           = var.zones
  kubernetes_version              = var.kubernetes_version
  sku_tier                        = var.aks.sku_tier
  local_account_disabled          = var.aks.local_account_disabled
  admin_group_object_ids          = var.aks.admin_group_object_ids
  deployer_object_id              = data.azurerm_client_config.current.object_id
  api_server_authorized_ip_ranges = var.aks.api_server_authorized_ip_ranges
  system_node_vm_size             = var.aks.system_node_vm_size
  system_node_min_count           = var.aks.system_node_min_count
  system_node_max_count           = var.aks.system_node_max_count
  workload_node_pool_name         = var.aks.workload_node_pool_name
  workload_node_vm_size           = var.aks.workload_node_vm_size
  workload_node_min_count         = var.aks.workload_node_min_count
  workload_node_max_count         = var.aks.workload_node_max_count
  node_os_disk_size_gb            = var.aks.node_os_disk_size_gb
  pod_cidr                        = var.aks.pod_cidr
  service_cidr                    = var.aks.service_cidr
  dns_service_ip                  = var.aks.dns_service_ip
  tags                            = local.tags

  # userAssignedNATGateway requires the NAT gateway to be on the subnet first.
  depends_on = [module.network]
}

# ---------------------------------------------------------------------------
# Generated credentials. Alphanumeric where the value ends up inside a
# connection URL, so nothing needs URL-encoding.
# ---------------------------------------------------------------------------

resource "random_password" "postgres" {
  length  = 40
  special = false
}

resource "random_password" "rabbitmq" {
  length  = 32
  special = false
}

# Interim in-cluster MinIO (until Plane ships its native Azure Blob provider).
resource "random_password" "minio" {
  length  = 32
  special = false
}

# The OpenSearch security plugin rejects passwords without a special character.
resource "random_password" "opensearch" {
  length           = 32
  special          = true
  override_special = "-_"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

# Plane's signing/encryption keys. SECRET_KEY and AES_SECRET_KEY encrypt data at
# rest: changing them later makes existing ciphertext unreadable, so they are
# generated once and never rotated by Terraform.
resource "random_password" "app_keys" {
  for_each = toset(["SECRET_KEY", "AES_SECRET_KEY", "LIVE_SERVER_SECRET_KEY", "PI_INTERNAL_SECRET", "SILO_HMAC_SECRET_KEY"])

  length  = 50
  special = false
}

module "postgres" {
  source = "./modules/postgres"

  name                         = local.unique_name
  location                     = var.location
  resource_group_name          = local.resource_group_name
  vnet_id                      = module.network.vnet_id
  subnet_id                    = module.network.postgres_subnet_id
  engine_version               = var.postgres.engine_version
  sku_name                     = var.postgres.sku_name
  storage_mb                   = var.postgres.storage_mb
  high_availability_mode       = var.postgres.high_availability_mode
  backup_retention_days        = var.postgres.backup_retention_days
  geo_redundant_backup_enabled = var.postgres.geo_redundant_backup_enabled
  administrator_login          = var.postgres.administrator_login
  administrator_password       = random_password.postgres.result
  database_names               = var.postgres.database_names
  tags                         = local.tags
}

module "redis" {
  source = "./modules/redis"

  name                        = local.unique_name
  location                    = var.location
  resource_group_name         = local.resource_group_name
  vnet_id                     = module.network.vnet_id
  private_endpoints_subnet_id = module.network.private_endpoints_subnet_id
  sku_name                    = var.redis.sku_name
  high_availability_enabled   = var.redis.high_availability_enabled
  clustering_policy           = var.redis.clustering_policy
  tags                        = local.tags
}

module "object_store" {
  source = "./modules/object_store"

  name                          = var.name
  location                      = var.location
  resource_group_name           = local.resource_group_name
  vnet_id                       = module.network.vnet_id
  private_endpoints_subnet_id   = module.network.private_endpoints_subnet_id
  account_name_prefix           = var.object_store.account_name_prefix
  replication_type              = var.object_store.replication_type
  container_name                = var.object_store.container_name
  versioning_enabled            = var.object_store.versioning_enabled
  soft_delete_retention_days    = var.object_store.soft_delete_retention_days
  public_network_access_enabled = var.object_store.public_network_access_enabled
  tags                          = local.tags
}

# Key Vault secrets are JSON documents whose key names match the plane-enterprise
# chart's external_secrets.* defaults (username / password / host / port), so an
# External Secrets `dataFrom.extract` mirrors them with no templating.
locals {
  key_vault_secrets = {
    plane-postgres = jsonencode({
      username = var.postgres.administrator_login
      password = random_password.postgres.result
      host     = module.postgres.fqdn
      port     = tostring(module.postgres.port)
      dbname   = var.postgres.database_names[0]
    })
    plane-redis = jsonencode({
      host     = module.redis.hostname
      port     = tostring(module.redis.port)
      password = module.redis.primary_access_key
    })
    plane-rabbitmq = jsonencode({
      username = "plane"
      password = random_password.rabbitmq.result
    })
    plane-opensearch = jsonencode({
      username = "plane"
      password = random_password.opensearch.result
    })
    plane-minio = jsonencode({
      username = "plane"
      password = random_password.minio.result
    })
    plane-app-keys = jsonencode({ for k, v in random_password.app_keys : k => v.result })
  }
}

module "key_vault" {
  source = "./modules/key_vault"

  name                          = var.name
  location                      = var.location
  resource_group_name           = local.resource_group_name
  vnet_id                       = module.network.vnet_id
  private_endpoints_subnet_id   = module.network.private_endpoints_subnet_id
  purge_protection_enabled      = var.key_vault.purge_protection_enabled
  soft_delete_retention_days    = var.key_vault.soft_delete_retention_days
  public_network_access_enabled = var.key_vault.public_network_access_enabled
  allowed_ips                   = var.key_vault.allowed_ips
  extra_allowed_ips             = [module.network.nat_public_ip]
  private_endpoint_enabled      = var.key_vault.private_endpoint_enabled
  secret_names                  = ["plane-postgres", "plane-redis", "plane-rabbitmq", "plane-opensearch", "plane-minio", "plane-app-keys"]
  secret_values                 = local.key_vault_secrets
  tags                          = local.tags
}

module "identity" {
  source = "./modules/identity"

  name                  = var.name
  location              = var.location
  resource_group_name   = local.resource_group_name
  oidc_issuer_url       = module.aks.oidc_issuer_url
  plane_namespace       = var.plane_namespace
  plane_service_account = var.plane_service_account
  eso_namespace         = var.plane_namespace
  eso_service_account   = var.eso_service_account
  storage_account_id    = module.object_store.storage_account_id
  key_vault_id          = module.key_vault.id
  tags                  = local.tags
}

module "public_ips" {
  source = "./modules/public_ips"

  name                      = var.name
  location                  = var.location
  resource_group_name       = local.resource_group_name
  zones                     = var.zones
  ingress_domain_name_label = var.ingress_domain_name_label
  email_enabled             = var.enable_email_public_ip
  tags                      = local.tags
}
