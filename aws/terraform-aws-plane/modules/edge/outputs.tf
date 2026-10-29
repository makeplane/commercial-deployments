output "load_balancer_dns_name" {
  description = "Hostname of the NLB in front of Traefik."
  value       = data.aws_lb.traefik.dns_name
}
