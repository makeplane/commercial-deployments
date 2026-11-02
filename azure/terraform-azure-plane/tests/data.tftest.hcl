# random isn't mocked: it runs for real.

mock_provider "azurerm" {
  mock_resource "azurerm_private_dns_zone" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/plane-test-rg/providers/Microsoft.Network/privateDnsZones/mock.example" }
  }
  mock_resource "azurerm_managed_redis" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/plane-test-rg/providers/Microsoft.Cache/redisEnterprise/mock" }
  }
  mock_resource "azurerm_postgresql_flexible_server" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/plane-test-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/mock" }
  }
  mock_resource "azurerm_key_vault" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/plane-test-rg/providers/Microsoft.KeyVault/vaults/mock" }
  }
  mock_resource "azurerm_storage_account" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/plane-test-rg/providers/Microsoft.Storage/storageAccounts/mock" }
  }
}
mock_provider "time" {}

variables {
  name                        = "plane-test"
  location                    = "eastus2"
  resource_group_name         = "plane-test-rg"
  tenant_id                   = "00000000-0000-0000-0000-000000000001"
  deployer_object_id          = "00000000-0000-0000-0000-000000000002"
  vnet_id                     = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/plane-test-rg/providers/Microsoft.Network/virtualNetworks/plane-test-vnet"
  postgres_subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/plane-test-rg/providers/Microsoft.Network/virtualNetworks/plane-test-vnet/subnets/postgres"
  private_endpoints_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/plane-test-rg/providers/Microsoft.Network/virtualNetworks/plane-test-vnet/subnets/pe"
  nat_public_ip               = "20.0.0.1"
  zones                       = ["1", "2", "3"]
  postgres = {
    engine_version               = "15"
    sku_name                     = "GP_Standard_D2ds_v5"
    storage_mb                   = 131072
    high_availability_mode       = "ZoneRedundant"
    backup_retention_days        = 14
    geo_redundant_backup_enabled = false
    deletion_protection          = true
  }
  redis              = { sku_name = "Balanced_B1", high_availability_enabled = true, clustering_policy = "NoCluster" }
  opensearch_enabled = true
  storage = {
    replication_type           = "ZRS"
    container_name             = "uploads"
    versioning_enabled         = true
    soft_delete_retention_days = 7
    deletion_protection        = true
  }
  key_vault = { purge_protection_enabled = true, soft_delete_retention_days = 30, allowed_ips = [], private_endpoint_enabled = false }
  tags      = {}
}

run "defaults" {
  command = plan
  module {
    source = "./modules/data"
  }

  assert {
    condition     = length(azurerm_management_lock.postgres) == 1 && length(azurerm_management_lock.storage) == 1
    error_message = "Deletion protection (on by default) must lock PostgreSQL and the storage account."
  }
  assert {
    condition     = azurerm_postgresql_flexible_server.this.version == "15" && azurerm_postgresql_flexible_server.this.high_availability[0].mode == "ZoneRedundant" && azurerm_postgresql_flexible_server.this.high_availability[0].standby_availability_zone == "2"
    error_message = "PostgreSQL 15, zone-redundant HA with the standby in the second zone."
  }
  assert {
    condition     = !azurerm_postgresql_flexible_server.this.public_network_access_enabled && azurerm_postgresql_flexible_server_configuration.require_secure_transport.value == "on"
    error_message = "PostgreSQL must be private and require TLS."
  }
  assert {
    condition     = toset(keys(azurerm_postgresql_flexible_server_database.this)) == toset(["plane", "plane_pi"])
    error_message = "Both databases (plane, plane_pi) are created by Terraform."
  }
  assert {
    condition     = toset(keys(azurerm_key_vault_secret.this)) == toset(["plane-db", "plane-redis", "plane-rabbitmq", "plane-opensearch", "plane-app-keys"])
    error_message = "Key Vault must hold exactly the secrets Plane reads."
  }
  assert {
    condition = toset(keys(random_password.app_keys)) == toset([
      "SECRET_KEY", "AES_SECRET_KEY", "AES_SALT", "LIVE_SERVER_SECRET_KEY", "PI_INTERNAL_SECRET",
      "SILO_HMAC_SECRET_KEY", "CURSOR_WEBHOOK_SECRET", "RUNNER_HMAC_SECRET_KEY",
    ])
    error_message = "The app keys must match the AWS module's list."
  }
  assert {
    condition     = !azurerm_storage_account.this.shared_access_key_enabled && azurerm_storage_account.this.public_network_access == "Disabled" && azurerm_storage_account.this.account_replication_type == "ZRS"
    error_message = "The storage account must have no shared keys, no public access, and ZRS by default."
  }
  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].versioning_enabled && azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days == 7
    error_message = "Blob versioning and soft delete must be on."
  }
  assert {
    condition     = azurerm_key_vault.this.rbac_authorization_enabled && azurerm_key_vault.this.purge_protection_enabled && azurerm_key_vault.this.network_acls[0].default_action == "Allow"
    error_message = "Key Vault: RBAC mode, purge protection, public endpoint by default."
  }
}

run "unprotected_without_opensearch" {
  command = plan
  module {
    source = "./modules/data"
  }
  variables {
    opensearch_enabled = false
    postgres = {
      engine_version               = "15"
      sku_name                     = "GP_Standard_D2ds_v5"
      storage_mb                   = 131072
      high_availability_mode       = "Disabled"
      backup_retention_days        = 7
      geo_redundant_backup_enabled = false
      deletion_protection          = false
    }
    storage = {
      replication_type           = "ZRS"
      container_name             = "uploads"
      versioning_enabled         = true
      soft_delete_retention_days = 7
      deletion_protection        = false
    }
    key_vault = { purge_protection_enabled = true, soft_delete_retention_days = 30, allowed_ips = ["203.0.113.10"], private_endpoint_enabled = true }
  }

  assert {
    condition     = length(azurerm_management_lock.postgres) == 0 && length(azurerm_management_lock.storage) == 0
    error_message = "deletion_protection = false must remove the locks."
  }
  assert {
    condition     = length(azurerm_postgresql_flexible_server.this.high_availability) == 0
    error_message = "high_availability_mode = Disabled must remove the HA block."
  }
  assert {
    condition     = !contains(keys(azurerm_key_vault_secret.this), "plane-opensearch")
    error_message = "No OpenSearch password without OpenSearch."
  }
  assert {
    condition     = azurerm_key_vault.this.network_acls[0].default_action == "Deny" && contains(azurerm_key_vault.this.network_acls[0].ip_rules, "20.0.0.1")
    error_message = "The Key Vault firewall must let the cluster's NAT IP through."
  }
  assert {
    condition     = length(azurerm_private_endpoint.key_vault) == 1
    error_message = "key_vault.private_endpoint_enabled must add a private endpoint."
  }
}

run "long_name" {
  module {
    source = "./modules/data"
  }
  variables {
    name = "plane-prod-eu-west-1"
  }


  assert {
    condition     = length(azurerm_key_vault.this.name) <= 24 && can(regex("^[a-zA-Z][a-zA-Z0-9-]+[a-zA-Z0-9]$", azurerm_key_vault.this.name)) && !strcontains(azurerm_key_vault.this.name, "--")
    error_message = "Key Vault name must be 3-24 characters with no consecutive hyphens."
  }
  assert {
    condition     = can(regex("^[a-z0-9]{3,24}$", azurerm_storage_account.this.name))
    error_message = "Storage account name must be 3-24 lowercase letters and digits."
  }
}
