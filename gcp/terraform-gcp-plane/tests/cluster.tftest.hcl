# How the GKE cluster skips its default node pool. Runs the cluster module alone with a mock provider.

mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      email  = "plane-test-nodes@plane-test-project.iam.gserviceaccount.com"
      member = "serviceAccount:plane-test-nodes@plane-test-project.iam.gserviceaccount.com"
      name   = "projects/plane-test-project/serviceAccounts/plane-test-nodes@plane-test-project.iam.gserviceaccount.com"
    }
  }
}

variables {
  name                       = "plane-test"
  project_id                 = "plane-test-project"
  region                     = "us-central1"
  zones                      = []
  network_id                 = "projects/plane-test-project/global/networks/plane-test"
  subnet_id                  = "projects/plane-test-project/regions/us-central1/subnetworks/plane-test"
  pods_range_name            = "plane-test-pods"
  services_range_name        = "plane-test-services"
  master_authorized_networks = ["0.0.0.0/0"]
  cluster_admin_members      = []
  labels                     = {}
  node_pool = {
    machine_type = "n2d-standard-4"
    min_per_zone = 1
    max_per_zone = 2
    disk_size_gb = 100
    disk_type    = "pd-balanced"
    spot         = false
  }
}

run "regular_creates_no_default_pool" {
  command = plan
  module {
    source = "./modules/cluster"
  }
  variables {
    release_channel = "REGULAR"
  }

  assert {
    condition     = google_container_cluster.this.initial_node_count == 0 && length(google_container_cluster.this.node_config) == 0
    error_message = "RAPID and REGULAR must create the cluster with no default node pool (initial_node_count 0, no node_config)."
  }
}

run "stable_keeps_removed_default_pool" {
  command = plan
  module {
    source = "./modules/cluster"
  }
  variables {
    release_channel = "STABLE"
  }

  assert {
    condition     = google_container_cluster.this.initial_node_count == 1
    error_message = "STABLE must still create and remove a one-node default pool (its GKE versions predate 1.36.4-gke.1469000)."
  }
  assert {
    condition     = length(google_container_cluster.this.node_config) == 1 && google_container_cluster.this.node_config[0].workload_metadata_config[0].mode == "GKE_METADATA"
    error_message = "STABLE's temporary default pool must keep the module's node settings (its own service account, GKE metadata)."
  }
}
