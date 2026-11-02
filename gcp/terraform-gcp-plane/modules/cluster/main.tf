# GKE Standard, regional: private nodes (no public IPs) in one node pool across the region's zones, a public API
# endpoint restricted by master_authorized_networks (as on AWS), Workload Identity, Dataplane V2 and shielded nodes.

# The nodes' own identity: logging, monitoring and image pulls only. Plane's pods never use it (Workload Identity).
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.name}-nodes"
  display_name = "Plane ${var.name} GKE nodes"
}

resource "google_project_iam_member" "nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = google_service_account.nodes.member
}

resource "google_container_cluster" "this" {
  # checkov:skip=CKV_GCP_24:PodSecurityPolicy was removed from Kubernetes; not applicable.
  # checkov:skip=CKV_GCP_66:Binary Authorization needs an attestation policy per organisation; customer choice.
  # checkov:skip=CKV_GCP_65:Google Groups for RBAC needs a Workspace groups domain; customer choice.
  # checkov:skip=CKV_GCP_12:Network policy enforcement is built into Dataplane V2 (ADVANCED_DATAPATH).
  # checkov:skip=CKV_GCP_18:The public endpoint is restricted by master_authorized_networks (default open, as on AWS).
  # checkov:skip=CKV_GCP_61:The subnet has flow logs; intranode visibility adds log volume and cost, customer choice.
  project        = var.project_id
  name           = var.name
  location       = var.region
  node_locations = length(var.zones) > 0 ? var.zones : null

  # The default pool is replaced by the managed pool below.
  remove_default_node_pool = true
  initial_node_count       = 1

  network         = var.network_id
  subnetwork      = var.subnet_id
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Private nodes; the control plane keeps a public endpoint, reachable only from master_authorized_networks.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value
        display_name = "authorized-${cidr_blocks.key}"
      }
    }
  }

  # No client certificates: access is through IAM only.
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = var.release_channel
  }

  datapath_provider     = "ADVANCED_DATAPATH"
  enable_shielded_nodes = true

  # Upgrades in a weekend night window (UTC).
  maintenance_policy {
    recurring_window {
      start_time = "2025-01-04T02:00:00Z"
      end_time   = "2025-01-04T08:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  addons_config {
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  # The temporary default pool also runs as the node service account, never the Compute Engine default one.
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  resource_labels = var.labels

  # As on AWS: Plane's data is protected by Cloud SQL's deletion protection and the bucket, not the cluster.
  deletion_protection = false

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }

  lifecycle {
    # node_config only describes the removed default pool; a change would recreate the cluster.
    ignore_changes = [node_config]
  }

  depends_on = [google_project_iam_member.nodes]
}

resource "google_container_node_pool" "this" {
  project  = var.project_id
  name     = "default"
  location = var.region
  cluster  = google_container_cluster.this.name

  # Per zone. GKE's cluster autoscaler scales between the bounds.
  initial_node_count = var.node_pool.min_per_zone
  autoscaling {
    min_node_count = var.node_pool.min_per_zone
    max_node_count = var.node_pool.max_per_zone
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Replace one node at a time, adding the new one first.
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.node_pool.machine_type
    disk_size_gb = var.node_pool.disk_size_gb
    disk_type    = var.node_pool.disk_type
    spot         = var.node_pool.spot
    image_type   = "COS_CONTAINERD"

    # Scopes are legacy: access is limited by the service account's IAM roles.
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    resource_labels = var.labels
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }

  lifecycle {
    # Set at creation only; the autoscaler owns the node count afterwards.
    ignore_changes = [initial_node_count]
  }
}

# GKE's admin role is project-wide (another reason to give Plane its own project).
resource "google_project_iam_member" "cluster_admin" {
  for_each = toset(var.cluster_admin_members)

  project = var.project_id
  role    = "roles/container.admin"
  member  = each.value
}
