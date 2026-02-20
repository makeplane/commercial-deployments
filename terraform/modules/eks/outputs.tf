output "cluster_id" {
  description = "ID of the EKS cluster"
  value       = aws_eks_cluster.main.id
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for cluster authentication"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID of the EKS cluster"
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "Security group ID of the EKS node group"
  value       = aws_security_group.node.id
}

output "node_group_id" {
  description = "EKS node group ID"
  value       = aws_eks_node_group.main.id
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the cluster (for IRSA)"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider for the cluster (for IRSA trust policies)"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "addon_versions" {
  description = "Versions of installed EKS add-ons"
  value = {
    vpc_cni      = aws_eks_addon.vpc_cni.addon_version
    kube_proxy   = aws_eks_addon.kube_proxy.addon_version
    coredns      = aws_eks_addon.coredns.addon_version
    cert_manager = aws_eks_addon.cert_manager.addon_version
    ebs_csi      = aws_eks_addon.ebs_csi.addon_version
  }
}
