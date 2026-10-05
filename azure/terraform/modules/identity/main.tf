# Azure Workload Identity: the Azure equivalent of IRSA. Each user-assigned
# identity trusts exactly one Kubernetes ServiceAccount through a federated
# credential on the cluster's OIDC issuer.

# Plane workloads (api, worker, silo, pi, ...) — object storage access.
resource "azurerm_user_assigned_identity" "plane" {
  name                = "${var.name}-plane-workload"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_federated_identity_credential" "plane" {
  name                      = "${var.name}-plane-workload"
  user_assigned_identity_id = azurerm_user_assigned_identity.plane.id
  issuer                    = var.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.plane_namespace}:${var.plane_service_account}"
  audience                  = ["api://AzureADTokenExchange"]
}

resource "azurerm_role_assignment" "plane_blob" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.plane.principal_id
  principal_type       = "ServicePrincipal"
}

# External Secrets Operator — reads the Key Vault secrets and mirrors them into
# Kubernetes Secrets for the Helm chart's external_secrets.* settings.
resource "azurerm_user_assigned_identity" "eso" {
  name                = "${var.name}-external-secrets"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_federated_identity_credential" "eso" {
  name                      = "${var.name}-external-secrets"
  user_assigned_identity_id = azurerm_user_assigned_identity.eso.id
  issuer                    = var.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.eso_namespace}:${var.eso_service_account}"
  audience                  = ["api://AzureADTokenExchange"]
}

resource "azurerm_role_assignment" "eso_key_vault" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.eso.principal_id
  principal_type       = "ServicePrincipal"
}
