locals {
  apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "redis.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "storage.googleapis.com",
  ]

  pods_range     = "${var.name}-pods"
  services_range = "${var.name}-services"
}

# Left on at destroy: other things in the project may use them.
resource "google_project_service" "this" {
  for_each = var.enable_apis ? toset(local.apis) : toset([])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# A newly enabled API can take a short while to accept requests everywhere.
resource "time_sleep" "apis" {
  count = var.enable_apis ? 1 : 0

  create_duration = "60s"

  depends_on = [google_project_service.this]
}

resource "google_compute_network" "this" {
  # checkov:skip=CKV2_GCP_18:No module firewall rules: GKE creates the ones it needs.
  project                 = var.project_id
  name                    = var.name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [time_sleep.apis]
}

resource "google_compute_subnetwork" "this" {
  project                  = var.project_id
  name                     = var.name
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.network.subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = local.pods_range
    ip_cidr_range = var.network.pods_cidr
  }

  secondary_ip_range {
    range_name    = local.services_range
    ip_cidr_range = var.network.services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_router" "this" {
  project = var.project_id
  name    = var.name
  region  = var.region
  network = google_compute_network.this.id
}

# Egress for the private nodes: Docker Hub, prime.plane.so, Helm repositories and the ACME server.
resource "google_compute_router_nat" "this" {
  project                            = var.project_id
  name                               = var.name
  region                             = var.region
  router                             = google_compute_router.this.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Cloud SQL and Memorystore get private IPs from this range.
resource "google_compute_global_address" "private_services" {
  project       = var.project_id
  name          = "${var.name}-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = split("/", var.network.private_service_cidr)[0]
  prefix_length = tonumber(split("/", var.network.private_service_cidr)[1])
  network       = google_compute_network.this.id
}

resource "google_service_networking_connection" "this" {
  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]

  # Deleting the peering fails while Cloud SQL and Memorystore still hold it; it goes with the VPC instead.
  deletion_policy = "ABANDON"
}
