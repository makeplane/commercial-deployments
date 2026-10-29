output "load_balancer_dns_name" {
  description = "Hostname of the NLB in front of Traefik (null in path B)."
  value       = var.install_traefik ? data.aws_lb.traefik[0].dns_name : null
}
