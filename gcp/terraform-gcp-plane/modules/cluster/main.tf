# Node identity only; Plane's pods use Workload Identity.
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
  # checkov:skip=CKV_GCP_18:The public endpoint is restricted by master_authorized_networks.
  # checkov:skip=CKV_GCP_21:Labels always set (root adds plane-deployment, managed-by); checkov can't always resolve them.
  # checkov:skip=CKV_GCP_61:The subnet has flow logs; intranode visibility adds cost, customer choice.
  project        = var.project_id
  name           = var.name
  location       = var.region
  node_locations = length(var.zones) > 0 ? var.zones : null

  # Deprecated by provider 8.9 but still works. Its replacement needs that provider and GKE 1.36.4-gke.1469000+,
  # newer than the STABLE channel's default (1.35), and changing it on a live cluster may force a rebuild.
  remove_default_node_pool = true
  initial_node_count       = 1

  network         = var.network_id
  subnetwork      = var.subnet_id
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

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
  # Internal LoadBalancer Services need GKE subsetting for their static-IP annotation (path A, scheme internal).
  enable_l4_ilb_subsetting = true

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

  # The temporary default pool must not run as the Compute Engine default service account.
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

  # Plane's data is protected by Cloud SQL's deletion protection, not the cluster's.
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

  # Per zone.
  initial_node_count = var.node_pool.min_per_zone
  autoscaling {
    min_node_count = var.node_pool.min_per_zone
    max_node_count = var.node_pool.max_per_zone
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

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

    # Scopes are legacy; the service account's IAM roles limit access.
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

# GKE's admin role is project-wide.
resource "google_project_iam_member" "cluster_admin" {
  for_each = toset(var.cluster_admin_members)

  project = var.project_id
  role    = "roles/container.admin"
  member  = each.value
}
