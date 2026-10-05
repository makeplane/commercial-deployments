output "cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_fqdn" {
  description = "FQDN of the AKS API server"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL used by workload identity federated credentials"
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "node_resource_group" {
  description = "Resource group holding the node VMs, disks and the managed load balancer"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "kubernetes_version" {
  description = "Running Kubernetes version"
  value       = azurerm_kubernetes_cluster.main.current_kubernetes_version
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet identity (grant AcrPull here when using ACR)"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
