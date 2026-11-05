output "plane_url" {
  description = "URL Plane is served on."
  value       = module.plane.plane_url
}

output "dns_records" {
  description = "The DNS records to create (the module creates none): an A record for domain, an MX record for email."
  value       = module.plane.dns_records
}

output "ssm_session_command" {
  description = "Shell on the instance (SSM Session Manager, no SSH)."
  value       = module.plane.ssm_session_command
}

output "rerun_setup_command" {
  description = "Run the setup again without a Terraform change."
  value       = module.plane.rerun_setup_command
}

output "ssm_output_s3_uri" {
  description = "Where the setup, backup and certificate jobs write their output."
  value       = module.plane.ssm_output_s3_uri
}
