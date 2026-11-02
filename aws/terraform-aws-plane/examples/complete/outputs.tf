output "plane_url" {
  description = "URL Plane is served on."
  value       = module.plane.plane_url
}

output "load_balancer_dns_name" {
  description = "Path A: Traefik NLB hostname (null in path B)."
  value       = module.plane.load_balancer_dns_name
}

output "configure_kubectl" {
  description = "Command to point kubectl at the cluster."
  value       = module.plane.configure_kubectl
}

output "email_load_balancer_dns_name" {
  description = "Email NLB hostname (the MX target for email.smtp_domain, default intake.<domain>)."
  value       = module.plane.email_load_balancer_dns_name
}

output "dns_records" {
  description = "The DNS records to create (the module creates none)."
  value       = module.plane.dns_records
}

output "plane_helm_values" {
  description = "Chart values the module generated (YAML, no secret values)."
  value       = module.plane.plane_helm_values
}
