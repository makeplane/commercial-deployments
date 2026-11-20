output "network_id" {
  description = "VPC network ID (projects/<project>/global/networks/<name>)."
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "VPC network name."
  value       = google_compute_network.this.name
}

output "subnet_id" {
  description = "Subnet ID. Released only after Cloud NAT exists, so nodes can pull images on first boot."
  value       = google_compute_subnetwork.this.id
  depends_on  = [google_compute_router_nat.this]
}

output "subnet_name" {
  description = "Subnet name."
  value       = google_compute_subnetwork.this.name
}

output "pods_range_name" {
  description = "Secondary range for GKE pods."
  value       = local.pods_range
}

output "services_range_name" {
  description = "Secondary range for GKE services."
  value       = local.services_range
}

output "private_service_range_name" {
  description = "Private services access range, available once the peering exists (Cloud SQL and Memorystore need it)."
  value       = google_compute_global_address.private_services.name
  depends_on  = [google_service_networking_connection.this]
}

output "project_id" {
  description = "project_id, available once the project APIs are enabled. Every other module takes the project from here, so nothing is created before its API is on."
  value       = var.project_id
  depends_on  = [time_sleep.apis]
}
