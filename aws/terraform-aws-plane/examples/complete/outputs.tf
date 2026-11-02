output "plane_url" {
  description = "URL Plane is served on."
  value       = module.plane.plane_url
}

output "load_balancer_dns_name" {
  description = "EKS path A: Traefik NLB hostname (null in path B and in Docker mode)."
  value       = module.plane.load_balancer_dns_name
}

output "configure_kubectl" {
  description = "EKS: command to point kubectl at the cluster."
  value       = module.plane.configure_kubectl
}

output "email_load_balancer_dns_name" {
  description = "EKS: email NLB hostname (the MX target for email.smtp_domain, default intake.<domain>)."
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

output "ssm_session_command" {
  description = "Docker mode: shell on the instance (SSM Session Manager, no SSH)."
  value       = module.plane.ssm_session_command
}

output "rerun_setup_command" {
  description = "Docker mode: run the setup again without a Terraform change."
  value       = module.plane.rerun_setup_command
}

output "ssm_output_s3_uri" {
  description = "Docker mode: where the setup, backup and certificate jobs write their output."
  value       = module.plane.ssm_output_s3_uri
}
