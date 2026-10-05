data "azurerm_client_config" "current" {}

resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Key Vault names are global, 3-24 chars: letters, digits and hyphens.
  vault_name = "${substr(replace(var.name, "/[^a-zA-Z0-9-]/", ""), 0, 14)}-kv-${random_id.suffix.hex}"
}

resource "azurerm_key_vault" "main" {
  name                = local.vault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = true
  purge_protection_enabled   = var.purge_protection_enabled
  soft_delete_retention_days = var.soft_delete_retention_days

  public_network_access_enabled = var.public_network_access_enabled

  # With allowed_ips set, only those addresses (plus the AKS egress IP, so External
  # Secrets Operator can read) reach the vault. Empty = open, still RBAC-gated.
  network_acls {
    bypass         = "AzureServices"
    default_action = length(var.allowed_ips) > 0 ? "Deny" : "Allow"
    ip_rules       = length(var.allowed_ips) > 0 ? concat(var.allowed_ips, var.extra_allowed_ips) : []
  }

  tags = var.tags
}

# Lets the identity running Terraform write the secrets below.
resource "azurerm_role_assignment" "deployer_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Role assignments take a short while to reach the Key Vault data plane; writing
# a secret immediately after granting the role fails with 403.
resource "time_sleep" "rbac_propagation" {
  create_duration = "60s"

  depends_on = [azurerm_role_assignment.deployer_secrets_officer]
}

resource "azurerm_key_vault_secret" "main" {
  for_each = toset(var.secret_names)

  name         = each.value
  value        = var.secret_values[each.value]
  key_vault_id = azurerm_key_vault.main.id
  content_type = "application/json"

  depends_on = [time_sleep.rbac_propagation]
}

resource "azurerm_private_dns_zone" "vault" {
  count = var.private_endpoint_enabled ? 1 : 0

  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "vault" {
  count = var.private_endpoint_enabled ? 1 : 0

  name                 = "${var.name}-vault-dns"
  private_dns_zone_id  = azurerm_private_dns_zone.vault[0].id
  virtual_network_id   = var.vnet_id
  registration_enabled = false

  tags = var.tags
}

resource "azurerm_private_endpoint" "vault" {
  count = var.private_endpoint_enabled ? 1 : 0

  name                = "${var.name}-vault-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id

  private_service_connection {
    name                           = "${var.name}-vault"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "vault"
    private_dns_zone_ids = [azurerm_private_dns_zone.vault[0].id]
  }

  tags = var.tags
}
