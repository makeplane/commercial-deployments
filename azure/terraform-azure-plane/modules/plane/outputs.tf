output "identity_client_id" {
  description = "Client ID of the managed identity Plane's pods use (Workload Identity)."
  value       = azurerm_user_assigned_identity.plane.client_id
}

output "namespace" {
  description = "Namespace Plane runs in."
  value       = local.namespace
}

output "release" {
  description = "Helm release name (fixed: part of the licence identity)."
  value       = helm_release.plane.name
}

output "rabbitmq_host" {
  description = "In-cluster RabbitMQ Service."
  value       = "${local.release}-rabbitmq.${local.namespace}.svc.${local.cluster_domain}"
}

output "helm_values" {
  description = "The plane-enterprise values the module generates (YAML), without the caller's plane_values."
  value       = yamlencode(local.values)
}
