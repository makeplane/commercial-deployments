output "ready" {
  description = "Available once every add-on release is installed (CRDs and webhooks ready). Gates the Plane release."
  value       = "ready"
  depends_on = [
    helm_release.traefik,
    helm_release.external_secrets,
    helm_release.cert_manager,
    helm_release.reloader,
  ]
}

output "external_secrets_service_account_email" {
  description = "Google service account External Secrets reads Secret Manager with."
  value       = google_service_account.external_secrets.email
}

output "cert_manager_enabled" {
  description = "Whether cert-manager is installed (the module issues the certificate)."
  value       = local.cert_manager_enabled
}

output "traefik_ingress_class" {
  description = "IngressClass / ingress controller name Plane routes through."
  value       = "traefik"
}
