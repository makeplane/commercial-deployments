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

output "email_load_balancer_dns_name" {
  description = "Email NLB hostname (MX target for email_smtp_domain when route53_zone_id is null)."
  value       = module.plane.email_load_balancer_dns_name
}
