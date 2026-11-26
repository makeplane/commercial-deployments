output "postgres_host" {
  description = "PostgreSQL Flexible Server FQDN."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "redis_host" {
  description = "Azure Managed Redis hostname."
  value       = azurerm_managed_redis.this.hostname
}

output "key_vault_id" {
  description = "Key Vault ID."
  value       = azurerm_key_vault.this.id
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = azurerm_key_vault.this.vault_uri
}

output "storage_account_name" {
  description = "Uploads storage account."
  value       = azurerm_storage_account.this.name
}

output "storage_container_name" {
  description = "Uploads container."
  value       = azurerm_storage_container.uploads.name
}

output "secret_ids" {
  description = "Versionless IDs of every Key Vault secret Plane reads."
  value       = { for k, s in azurerm_key_vault_secret.this : k => s.versionless_id }
}

output "plane_inputs" {
  description = "Everything the Plane Helm release needs from the data layer."
  value = {
    key_vault_uri = azurerm_key_vault.this.vault_uri

    postgres_host        = azurerm_postgresql_flexible_server.this.fqdn
    postgres_port        = 5432
    postgres_db          = azurerm_postgresql_flexible_server_database.this["plane"].name
    postgres_secret_name = azurerm_key_vault_secret.this["plane-db"].name

    redis_host        = azurerm_managed_redis.this.hostname
    redis_port        = azurerm_managed_redis.this.default_database[0].port
    redis_secret_name = azurerm_key_vault_secret.this["plane-redis"].name

    rabbitmq_secret_name   = azurerm_key_vault_secret.this["plane-rabbitmq"].name
    opensearch_secret_name = var.opensearch_enabled ? azurerm_key_vault_secret.this["plane-opensearch"].name : null
    app_keys_secret_name   = azurerm_key_vault_secret.this["plane-app-keys"].name
    app_key_names          = keys(random_password.app_keys)

    storage_account_name   = azurerm_storage_account.this.name
    storage_container_name = azurerm_storage_container.uploads.name
    storage_container_id   = azurerm_storage_container.uploads.id
    storage_blob_endpoint  = azurerm_storage_account.this.primary_blob_endpoint
  }

  # Every service must be reachable before Plane's pods start.
  depends_on = [
    azurerm_postgresql_flexible_server_configuration.require_secure_transport,
    azurerm_postgresql_flexible_server_database.this,
    azurerm_private_endpoint.redis,
    azurerm_private_dns_zone_virtual_network_link.redis,
    azurerm_private_endpoint.blob,
    azurerm_private_dns_zone_virtual_network_link.blob,
  ]
}
