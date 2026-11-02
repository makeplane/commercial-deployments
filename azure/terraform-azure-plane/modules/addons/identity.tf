# External Secrets' Workload Identity: a user-assigned identity trusted for exactly the controller's
# ServiceAccount, allowed to read secrets from the module's Key Vault and the customer's certificates.
# Adapted from azure/terraform/modules/identity (ESO half).

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

# The customer's certificates (path A web, email), each scoped to its own backing secret.
resource "azurerm_role_assignment" "external_secrets_certificates" {
  for_each = toset(var.certificate_scopes)

  scope                = each.value
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.external_secrets.principal_id
  principal_type       = "ServicePrincipal"
}
