output "iam_role_arn" {
  description = "IAM role Plane's pods use through Pod Identity."
  value       = module.plane_pod_identity.iam_role_arn
}

output "namespace" {
  description = "Namespace Plane runs in."
  value       = local.namespace
}

output "release" {
  description = "Helm release name (fixed: part of the licence identity)."
  value       = helm_release.plane.name
}

output "email_load_balancer_dns_name" {
  description = "Hostname of the email NLB (null when email is off)."
  value       = var.email.enabled ? data.aws_lb.email[0].dns_name : null
}
