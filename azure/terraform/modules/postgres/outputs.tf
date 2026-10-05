output "server_id" {
  description = "ID of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.main.id
}

output "fqdn" {
  description = "Private FQDN of the server (resolvable inside the VNet)"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "port" {
  description = "PostgreSQL port"
  value       = 5432
}

output "database_names" {
  description = "Databases created on the server"
  value       = [for db in azurerm_postgresql_flexible_server_database.main : db.name]
}
