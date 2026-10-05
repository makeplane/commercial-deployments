resource "random_id" "account_suffix" {
  byte_length = 4
}

locals {
  # Storage account names are global, 3-24 chars, lowercase letters and digits only.
  account_name = substr("${lower(replace(var.account_name_prefix, "/[^a-zA-Z0-9]/", ""))}${random_id.account_suffix.hex}", 0, 24)
}

resource "azurerm_storage_account" "main" {
  name                     = local.account_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  access_tier              = "Hot"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  # Entra ID (workload identity) only — no account keys, no SAS signed with them.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  # Plane runs in storage-proxy mode on Azure, so browsers never talk to Blob
  # directly and the account can stay off the internet.
  public_network_access = var.public_network_access_enabled ? "Enabled" : "Disabled"

  blob_properties {
    versioning_enabled = var.versioning_enabled

    delete_retention_policy {
      days = var.soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.soft_delete_retention_days
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "uploads" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                 = "${var.name}-blob-dns"
  private_dns_zone_id  = azurerm_private_dns_zone.blob.id
  virtual_network_id   = var.vnet_id
  registration_enabled = false

  tags = var.tags
}

resource "azurerm_private_endpoint" "blob" {
  name                = "${var.name}-blob-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id

  private_service_connection {
    name                           = "${var.name}-blob"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }

  tags = var.tags
}
