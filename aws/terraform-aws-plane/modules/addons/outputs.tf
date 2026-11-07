output "ready" {
  description = "Available once every add-on release is installed (CRDs and webhooks ready). Gates the Plane release, so on destroy Plane (and its email NLB) goes first, then the NLB cleanup wait, then the LB controller."
  value       = "ready"
  depends_on = [
    helm_release.aws_load_balancer_controller,
    # Directly, not only through Traefik: in path B the email Service's NLB needs the wait too.
    time_sleep.nlb_cleanup,
    helm_release.traefik,
    helm_release.external_secrets,
    helm_release.cert_manager,
    helm_release.reloader,
    helm_release.metrics_server,
  ]
}

output "load_balancer_name" {
  description = "Name of the NLB the AWS Load Balancer Controller creates for Traefik."
  value       = local.load_balancer_name
}

output "cert_manager_enabled" {
  description = "Whether cert-manager is installed (the module issues the certificate)."
  value       = local.cert_manager_enabled
}

output "traefik_ingress_class" {
  description = "IngressClass / ingress controller name Plane routes through."
  value       = "traefik"
}
