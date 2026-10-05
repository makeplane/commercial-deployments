output "id" {
  description = "ID of the Managed Redis instance"
  value       = azurerm_managed_redis.main.id
}

output "hostname" {
  description = "Redis hostname (resolves to the private endpoint inside the VNet)"
  value       = azurerm_managed_redis.main.hostname
}

output "port" {
  description = "Redis TLS port"
  value       = azurerm_managed_redis.main.default_database[0].port
}

output "primary_access_key" {
  description = "Redis access key (used as REDIS_PASSWORD)"
  value       = azurerm_managed_redis.main.default_database[0].primary_access_key
  sensitive   = true
}
