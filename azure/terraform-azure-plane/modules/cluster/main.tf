locals {
  # The deployer administers the cluster (as the EKS cluster creator).
  cluster_admins = toset(concat([var.deployer_object_id], var.cluster_admin_object_ids))
}

# User-assigned so it gets Network Contributor before the cluster exists; with a BYO subnet and
# NAT gateway, cluster creation fails otherwise.
resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "${var.name}-aks-control-plane"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Resource-group scope: the static public IPs live here, not in the node resource group.
resource "azurerm_role_assignment" "control_plane_network" {
  scope                = var.resource_group_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

# Role assignments take a minute to propagate; otherwise the cluster's subnet check fails.
resource "time_sleep" "control_plane_rbac" {
  create_duration = "60s"

  depends_on = [azurerm_role_assignment.control_plane_network]
}

resource "azurerm_kubernetes_cluster" "this" {
  # checkov:skip=CKV_AZURE_4:Container Insights is the customer's choice.
  # checkov:skip=CKV_AZURE_6:Restrictable via api_server_authorized_ip_ranges; open by default as on AWS.
  # checkov:skip=CKV_AZURE_115:A private cluster needs Terraform inside the VNet; later option.
  # checkov:skip=CKV_AZURE_116:Azure Policy add-on is the customer's choice.
  # checkov:skip=CKV_AZURE_117:Platform-managed disk encryption; CMK is a later option.
  # checkov:skip=CKV_AZURE_226:Ephemeral OS disks depend on the VM size's cache.
  # checkov:skip=CKV_AZURE_227:Encryption at host needs a subscription feature registration.
  # checkov:skip=CKV_AZURE_172:External Secrets syncs Key Vault, not the Secrets Store CSI driver.
  # checkov:skip=CKV_AZURE_232:One node pool runs system and Plane pods (parity with AWS).
  # checkov:skip=CKV_AZURE_168:Azure CNI Overlay defaults to 250 pods per node.
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version
  node_resource_group = "${var.resource_group_name}-${var.name}-nodes"
  sku_tier            = var.node_pool.sku_tier

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  local_account_disabled            = true
  role_based_access_control_enabled = true
  run_command_enabled               = false

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = var.tenant_id
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  # No critical-addons taint: Plane runs on the system pool too.
  default_node_pool {
    name                        = "system"
    vm_size                     = var.node_pool.vm_size
    vnet_subnet_id              = var.subnet_id
    zones                       = var.zones
    auto_scaling_enabled        = true
    min_count                   = var.node_pool.min_count
    max_count                   = var.node_pool.max_count
    node_count                  = var.node_pool.node_count
    os_disk_size_gb             = var.node_pool.os_disk_size_gb
    os_sku                      = "AzureLinux"
    temporary_name_for_rotation = "systemtmp"

    # The in-cluster OpenSearch needs vm.max_map_count >= 262144.
    linux_os_config {
      sysctl_config {
        vm_max_map_count = 262144
      }
    }

    upgrade_settings {
      max_surge = "33%"
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
    outbound_type       = "userAssignedNATGateway"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
  }

  node_provisioning_profile {
    mode = "Manual"
  }

  storage_profile {
    disk_driver_enabled         = true
    file_driver_enabled         = false
    blob_driver_enabled         = false
    snapshot_controller_enabled = true
  }

  dynamic "api_server_access_profile" {
    for_each = length(var.api_server_authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
  }

  tags = var.tags

  depends_on = [time_sleep.control_plane_rbac]

  lifecycle {
    ignore_changes = [
      # Owned by the cluster autoscaler.
      default_node_pool[0].node_count,
    ]
  }
}

resource "azurerm_role_assignment" "cluster_admin" {
  for_each = local.cluster_admins

  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
}

# Azure RBAC takes minutes to reach the API server; Helm gets 403 before that.
resource "time_sleep" "cluster_rbac" {
  create_duration = "120s"

  depends_on = [azurerm_role_assignment.cluster_admin]
}
