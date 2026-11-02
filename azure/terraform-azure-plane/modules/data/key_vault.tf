# Key Vault in RBAC mode with purge protection. Its public endpoint stays on, gated by Entra ID RBAC
# (as Secrets Manager on AWS); key_vault.allowed_ips turns on the firewall and
# key_vault.private_endpoint_enabled adds a private endpoint. Adapted from azure/terraform/modules/key_vault.

resource "azurerm_key_vault" "this" {
  # checkov:skip=CKV_AZURE_109:The firewall is an input (key_vault.allowed_ips); off by default, access is RBAC-gated as Secrets Manager on AWS.
  # checkov:skip=CKV_AZURE_189:Public endpoint by default (Terraform and External Secrets reach it); key_vault.allowed_ips and private_endpoint_enabled restrict it.
  # checkov:skip=CKV2_AZURE_32:The private endpoint is an input (key_vault.private_endpoint_enabled).
  name                = local.key_vault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = true
  purge_protection_enabled   = var.key_vault.purge_protection_enabled
  soft_delete_retention_days = var.key_vault.soft_delete_retention_days

  public_network_access_enabled = true

  # With allowed_ips, only those addresses (plus the cluster's NAT IP, so External Secrets can read)
  # reach the vault. Empty: open, still RBAC-gated.
  network_acls {
    bypass         = "AzureServices"
    default_action = length(var.key_vault.allowed_ips) > 0 ? "Deny" : "Allow"
    ip_rules       = length(var.key_vault.allowed_ips) > 0 ? concat(var.key_vault.allowed_ips, [var.nat_public_ip]) : []
  }

  tags = var.tags
}

# Lets the identity running Terraform write the secrets.
resource "azurerm_role_assignment" "deployer_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.deployer_object_id
}

# Role assignments take a while to reach the Key Vault data plane; writing a secret right after
# granting the role fails with 403.
resource "time_sleep" "key_vault_rbac" {
  create_duration = "60s"

  depends_on = [azurerm_role_assignment.deployer_secrets_officer]
}

resource "azurerm_private_dns_zone" "key_vault" {
  count = var.key_vault.private_endpoint_enabled ? 1 : 0

  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  count = var.key_vault.private_endpoint_enabled ? 1 : 0

  name                 = "${var.name}-key-vault-dns"
  private_dns_zone_id  = azurerm_private_dns_zone.key_vault[0].id
  virtual_network_id   = var.vnet_id
  registration_enabled = false

  tags = var.tags
}

resource "azurerm_private_endpoint" "key_vault" {
  count = var.key_vault.private_endpoint_enabled ? 1 : 0

  name                = "${var.name}-key-vault-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id

  private_service_connection {
    name                           = "${var.name}-key-vault"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "key-vault"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault[0].id]
  }

  tags = var.tags
}
