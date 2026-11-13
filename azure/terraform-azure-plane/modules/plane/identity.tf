# Pods bind to this identity via the Blob contract's serviceAccount annotations/podLabels in main.tf.

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

# Scoped to the uploads container, not the whole account.
resource "azurerm_role_assignment" "plane_blob" {
  scope                = var.data.storage_container_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.plane.principal_id
  principal_type       = "ServicePrincipal"
}

# The role and federated credential take a while to propagate; Plane's first Blob calls would get 403.
resource "time_sleep" "plane_identity" {
  create_duration = "60s"

  depends_on = [azurerm_federated_identity_credential.plane, azurerm_role_assignment.plane_blob]
}
