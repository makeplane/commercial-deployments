output "plane_url" {
  description = "URL Plane is served on."
  value       = module.plane.plane_url
}

output "load_balancer_dns_name" {
  description = "Load balancer hostname (point domain here with a CNAME when route53_zone_id is null)."
  value       = module.plane.load_balancer_dns_name
}

output "configure_kubectl" {
  description = "Command to point kubectl at the cluster."
  value       = module.plane.configure_kubectl
}
