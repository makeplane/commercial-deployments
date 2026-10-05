output "plane_client_id" {
  description = "Client ID of the Plane workload identity (azure.workload.identity/client-id)"
  value       = azurerm_user_assigned_identity.plane.client_id
}

output "plane_principal_id" {
  description = "Principal ID of the Plane workload identity"
  value       = azurerm_user_assigned_identity.plane.principal_id
}

output "eso_client_id" {
  description = "Client ID of the External Secrets identity"
  value       = azurerm_user_assigned_identity.eso.client_id
}
