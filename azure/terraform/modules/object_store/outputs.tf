output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "blob_endpoint" {
  description = "Blob service endpoint"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "container_name" {
  description = "Blob container for Plane uploads"
  value       = azurerm_storage_container.uploads.name
}
