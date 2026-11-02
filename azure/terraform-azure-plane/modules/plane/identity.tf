# Plane's pods reach Blob Storage through Azure Workload Identity: no account keys or SAS anywhere.
# The chart's ServiceAccount is "<release>-srv-account"; the federated credential trusts exactly it,
# and the chart's serviceAccount.annotations / podLabels (the Blob contract block in main.tf) bind
# the pods to this identity. Adapted from azure/terraform/modules/identity (Plane half).

resource "azurerm_user_assigned_identity" "plane" {
  name                = "${var.name}-plane"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_federated_identity_credential" "plane" {
  name                      = "${var.name}-plane"
  user_assigned_identity_id = azurerm_user_assigned_identity.plane.id
  issuer                    = var.oidc_issuer_url
  subject                   = "system:serviceaccount:${local.namespace}:${local.service_account}"
  audience                  = ["api://AzureADTokenExchange"]
}

# Read, write and delete blobs in the uploads container only (not the whole account).
resource "azurerm_role_assignment" "plane_blob" {
  scope                = var.data.storage_container_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.plane.principal_id
  principal_type       = "ServicePrincipal"
}
