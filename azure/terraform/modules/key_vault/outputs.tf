output "id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "vault_uri" {
  description = "URI of the Key Vault (SecretStore spec.provider.azurekv.vaultUrl)"
  value       = azurerm_key_vault.main.vault_uri
}

output "secret_names" {
  description = "Names of the secrets stored in the vault"
  value       = [for s in azurerm_key_vault_secret.main : s.name]
}
