output "service_account_email" {
  description = "Google service account Plane's pods use through Workload Identity."
  value       = google_service_account.plane.email
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
  description = "In-cluster RabbitMQ (AMQP, port 5672) host."
  value       = local.rabbitmq_host
}

output "helm_values" {
  description = "The plane-enterprise values the module generates (YAML), without the caller's plane_values."
  value       = yamlencode(local.values)
}
