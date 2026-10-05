locals {
  name_prefix = var.name
}

# Control-plane identity. User-assigned (rather than system-assigned) so it can be
# granted Network Contributor BEFORE the cluster exists: with a bring-your-own
# subnet and a user-assigned NAT gateway, cluster creation fails without it.
resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "${local.name_prefix}-aks-control-plane"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Network Contributor on the resource group covers the VNet/subnet joins and lets
# the cloud provider attach the pre-created ingress/email public IPs (which live
# in this resource group, not the node resource group) to LoadBalancer Services.
resource "azurerm_role_assignment" "control_plane_network" {
  scope                = var.resource_group_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

# A fresh role assignment takes a minute to propagate; creating the cluster
# immediately fails its subnet permission check.
resource "time_sleep" "control_plane_rbac" {
  create_duration = "60s"

  depends_on = [azurerm_role_assignment.control_plane_network]
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = local.name_prefix
  kubernetes_version  = var.kubernetes_version
  node_resource_group = "${var.resource_group_name}-${local.name_prefix}-nodes"
  sku_tier            = var.sku_tier

  automatic_upgrade_channel = var.automatic_upgrade_channel
  node_os_upgrade_channel   = "NodeImage"

  # Workload Identity: pods exchange their ServiceAccount token for an Entra token
  # (the Azure equivalent of IRSA).
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Entra ID authentication with Azure RBAC for Kubernetes authorization.
  local_account_disabled            = var.local_account_disabled
  role_based_access_control_enabled = true

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  # System pool: CoreDNS, metrics-server, CSI drivers and other critical add-ons only.
  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_vm_size
    vnet_subnet_id               = var.subnet_id
    zones                        = var.zones
    auto_scaling_enabled         = true
    min_count                    = var.system_node_min_count
    max_count                    = var.system_node_max_count
    os_disk_size_gb              = var.node_os_disk_size_gb
    os_sku                       = "AzureLinux"
    only_critical_addons_enabled = true
    temporary_name_for_rotation  = "systemtmp"

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
      # Managed by the cluster autoscaler.
      default_node_pool[0].node_count,
    ]
  }
}

# User pool: runs the Plane workloads (and the in-cluster RabbitMQ / OpenSearch).
resource "azurerm_kubernetes_cluster_node_pool" "workload" {
  name                  = var.workload_node_pool_name
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  mode                  = "User"
  vm_size               = var.workload_node_vm_size
  vnet_subnet_id        = var.subnet_id
  zones                 = var.zones
  auto_scaling_enabled  = true
  min_count             = var.workload_node_min_count
  max_count             = var.workload_node_max_count
  os_disk_size_gb       = var.node_os_disk_size_gb
  os_sku                = "AzureLinux"

  upgrade_settings {
    max_surge = "33%"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [node_count]
  }
}

# Equivalent of EKS bootstrap_cluster_creator_admin_permissions: whoever runs
# Terraform can administer the cluster through Entra ID.
resource "azurerm_role_assignment" "deployer_cluster_admin" {
  count = var.deployer_object_id != null ? 1 : 0

  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.deployer_object_id
}
