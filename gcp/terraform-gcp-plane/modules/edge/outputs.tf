# Consumers depend on the cleanup wait, so destroy runs: consumers, the wait, the addresses.

output "web_address_name" {
  description = "Name of the reserved address for Traefik's load balancer (null in path B)."
  value       = var.install_traefik ? google_compute_address.web[0].name : null
  depends_on  = [time_sleep.lb_cleanup]
}

output "web_ip" {
  description = "Traefik's load balancer IP (null in path B)."
  value       = var.install_traefik ? google_compute_address.web[0].address : null
}

output "email_address_name" {
  description = "Name of the reserved address for the email load balancer (null without one)."
  value       = var.email_load_balancer ? google_compute_address.email[0].name : null
  depends_on  = [time_sleep.lb_cleanup]
}

output "email_ip" {
  description = "Email load balancer IP (null without one)."
  value       = var.email_load_balancer ? google_compute_address.email[0].address : null
}
