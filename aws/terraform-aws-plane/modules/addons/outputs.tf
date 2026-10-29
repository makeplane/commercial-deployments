output "ready" {
  description = "Available once every add-on release is installed (CRDs and webhooks ready). Gates the Plane release."
  value       = "ready"
  depends_on = [
    helm_release.aws_load_balancer_controller,
    helm_release.traefik,
    helm_release.external_secrets,
    helm_release.cert_manager,
    helm_release.reloader,
    helm_release.metrics_server,
  ]
}

output "cert_manager_enabled" {
  description = "Whether cert-manager is installed (Route 53 DNS-01)."
  value       = local.cert_manager_enabled
}

output "traefik_ingress_class" {
  description = "IngressClass / ingress controller name Plane routes through."
  value       = "traefik"
}
