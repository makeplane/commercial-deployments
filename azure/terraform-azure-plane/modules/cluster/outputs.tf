output "cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_id" {
  description = "AKS cluster ID."
  value       = azurerm_kubernetes_cluster.this.id
}

output "cluster_endpoint" {
  description = "AKS API endpoint."
  value       = "https://${azurerm_kubernetes_cluster.this.fqdn}:443"
}

output "cluster_certificate_authority_data" {
  description = "AKS cluster CA (base64). Public data; kube_config, which carries it, is sensitive as a whole."
  value       = nonsensitive(azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL the Workload Identity federated credentials trust."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "node_resource_group" {
  description = "Resource group AKS manages (nodes, disks, the cluster load balancer)."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "ready" {
  description = "Cluster name, available only once the node pool is up and the admins' Azure RBAC roles have propagated."
  value       = azurerm_kubernetes_cluster.this.name
  depends_on  = [time_sleep.cluster_rbac]
}
