output "plane_url" {
  description = "URL Plane is served on."
  value       = module.plane.plane_url
}

output "load_balancer_ip" {
  description = "Path A: Traefik's load balancer IP (null in path B)."
  value       = module.plane.load_balancer_ip
}

output "email_load_balancer_ip" {
  description = "Email load balancer IP (the A record of email.smtp_domain, default intake.<domain>)."
  value       = module.plane.email_load_balancer_ip
}

output "configure_kubectl" {
  description = "Command to point kubectl at the cluster."
  value       = module.plane.configure_kubectl
}

output "dns_records" {
  description = "The DNS records to create (the module creates none)."
  value       = module.plane.dns_records
}

output "plane_helm_values" {
  description = "Chart values the module generated (YAML, no secret values)."
  value       = module.plane.plane_helm_values
}

output "resource_group_name" {
  description = "Resource group holding the deployment."
  value       = module.plane.resource_group_name
}

output "nat_public_ip" {
  description = "Egress IP of the cluster. Allow-list it where Plane calls out, and on a firewalled Key Vault of yours."
  value       = module.plane.nat_public_ip
}

output "postgres_endpoint" {
  description = "PostgreSQL Flexible Server FQDN (private, resolves inside the VNet)."
  value       = module.plane.postgres_endpoint
}

output "storage_account_name" {
  description = "Storage account for uploads (Blob)."
  value       = module.plane.storage_account_name
}

output "key_vault_uri" {
  description = "URI of the Key Vault holding the generated secrets."
  value       = module.plane.key_vault_uri
}
