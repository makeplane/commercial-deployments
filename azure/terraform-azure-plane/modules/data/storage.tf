# Plane proxies uploads through its API, so the account can stay private with no CORS, SAS or keys.

resource "azurerm_storage_account" "this" {
  # checkov:skip=CKV2_AZURE_1:Platform-managed keys; CMK is a later option.
  # checkov:skip=CKV_AZURE_206:Replication is an input (storage.replication_type); ZRS by default.
  # checkov:skip=CKV2_AZURE_33:Has a blob private endpoint (azurerm_private_endpoint.blob).
  # checkov:skip=CKV2_AZURE_38:Soft delete is on; checkov can't read optional() defaults.
  # checkov:skip=CKV2_AZURE_40:Shared keys are off.
  # checkov:skip=CKV2_AZURE_41:No SAS: shared keys are off.
  # checkov:skip=CKV_AZURE_33:No queues are used.
  # checkov:skip=CKV_AZURE_59:Public access is disabled; checkov reads only the deprecated attribute.
  name                     = local.storage_account_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.storage.replication_type
  access_tier              = "Hot"

  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
  local_user_enabled               = false

  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  public_network_access = "Disabled"

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    versioning_enabled = var.storage.versioning_enabled

    delete_retention_policy {
      days = var.storage.soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.storage.soft_delete_retention_days
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "uploads" {
  # checkov:skip=CKV2_AZURE_21:Read logging needs a diagnostic setting; the customer's choice.
  name                  = var.storage.container_name
  storage_account_id    = azurerm_storage_account.this.id
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
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }

  tags = var.tags
}

# Set storage.deletion_protection = false and apply before a destroy.
resource "azurerm_management_lock" "storage" {
  count = var.storage.deletion_protection ? 1 : 0

  name       = "${var.name}-storage-protect"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Plane uploads. Set storage.deletion_protection = false and apply before destroying."
}
