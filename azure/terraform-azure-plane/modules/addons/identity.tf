resource "azurerm_user_assigned_identity" "external_secrets" {
  name                = "${var.name}-external-secrets"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_federated_identity_credential" "external_secrets" {
  name                      = "${var.name}-external-secrets"
  user_assigned_identity_id = azurerm_user_assigned_identity.external_secrets.id
  issuer                    = var.oidc_issuer_url
  subject                   = "system:serviceaccount:${local.external_secrets_namespace}:${local.external_secrets_sa}"
  audience                  = ["api://AzureADTokenExchange"]
}

resource "azurerm_role_assignment" "external_secrets_key_vault" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.external_secrets.principal_id
  principal_type       = "ServicePrincipal"
}

# Each scoped to the certificate's own backing secret.
resource "azurerm_role_assignment" "external_secrets_certificates" {
  for_each = toset(var.certificate_scopes)

  scope                = each.value
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.external_secrets.principal_id
  principal_type       = "ServicePrincipal"
}
