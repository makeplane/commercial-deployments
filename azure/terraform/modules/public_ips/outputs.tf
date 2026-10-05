output "ingress_ip" {
  description = "Ingress public IP address"
  value       = azurerm_public_ip.ingress.ip_address
}

output "ingress_ip_name" {
  description = "Name of the ingress public IP (azure-pip-name annotation)"
  value       = azurerm_public_ip.ingress.name
}

output "ingress_fqdn" {
  description = "FQDN of the ingress IP when a domain_name_label is set"
  value       = azurerm_public_ip.ingress.fqdn
}

output "email_ip" {
  description = "Email public IP address (null when disabled)"
  value       = var.email_enabled ? azurerm_public_ip.email[0].ip_address : null
}

output "email_ip_name" {
  description = "Name of the email public IP (null when disabled)"
  value       = var.email_enabled ? azurerm_public_ip.email[0].name : null
}
