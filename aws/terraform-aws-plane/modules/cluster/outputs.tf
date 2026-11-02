output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster CA (base64)."
  value       = module.eks.cluster_certificate_authority_data
}

output "ready" {
  description = "Cluster name, available only once the whole EKS module (node group, add-ons, access entries) is done."
  value       = module.eks.cluster_name
  depends_on  = [module.eks]
}

output "node_security_group_id" {
  description = "Security group attached to the nodes; data services accept traffic only from it."
  value       = module.eks.node_security_group_id
}
