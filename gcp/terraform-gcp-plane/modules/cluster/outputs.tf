output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_endpoint" {
  description = "GKE API endpoint (https URL of the public endpoint)."
  value       = "https://${google_container_cluster.this.endpoint}"
}

output "cluster_certificate_authority_data" {
  description = "GKE cluster CA (base64)."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
}

output "workload_pool" {
  description = "Workload Identity pool (<project>.svc.id.goog)."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "ready" {
  description = "Cluster name, available only once the node pool and the admin grants are in place."
  value       = google_container_cluster.this.name
  depends_on  = [google_container_node_pool.this, google_project_iam_member.cluster_admin]
}
