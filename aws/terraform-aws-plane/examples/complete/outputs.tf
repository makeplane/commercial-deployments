output "plane_url" {
  description = "URL Plane is served on."
  value       = module.plane.plane_url
}

output "public_ips" {
  description = "Load balancer IPs (create the DNS record here when route53_zone_id is null)."
  value       = module.plane.public_ips
}

output "configure_kubectl" {
  description = "Command to point kubectl at the cluster."
  value       = module.plane.configure_kubectl
}
