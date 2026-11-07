output "ingress_public_ip" {
  description = "Static public IP of Traefik's load balancer (null unless path A, internet-facing)."
  value       = var.ingress_public_ip ? azurerm_public_ip.ingress[0].ip_address : null
}

output "ingress_public_ip_name" {
  description = "Name of Traefik's public IP resource (null unless path A, internet-facing)."
  value       = var.ingress_public_ip ? azurerm_public_ip.ingress[0].name : null
}

output "email_public_ip" {
  description = "Static public IP of the email load balancer (null without it)."
  value       = var.email_public_ip ? azurerm_public_ip.email[0].ip_address : null
}

output "email_public_ip_name" {
  description = "Name of the email public IP resource (null without it)."
  value       = var.email_public_ip ? azurerm_public_ip.email[0].name : null
}
