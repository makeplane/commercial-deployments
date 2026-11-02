# AKS with Entra ID + Azure RBAC (no local accounts), Workload Identity, Azure CNI Overlay with Cilium,
# egress through the NAT gateway, and one autoscaled node pool. Adapted from azure/terraform/modules/aks.

locals {
  # Whoever runs Terraform administers the cluster (the EKS cluster-creator equivalent), plus the extra admins.
  cluster_admins = toset(concat([var.deployer_object_id], var.cluster_admin_object_ids))
}

# Control-plane identity. User-assigned, so it can be granted Network Contributor before the cluster
# exists: with a bring-your-own subnet and a user-assigned NAT gateway, cluster creation fails without it.
resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "${var.name}-aks-control-plane"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Network Contributor on the resource group covers the subnet join and lets the cloud provider attach
# the module's static public IPs (they live in this resource group, not the node resource group).
resource "azurerm_role_assignment" "control_plane_network" {
  scope                = var.resource_group_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

# A new role assignment takes a minute to propagate; creating the cluster at once fails its subnet check.
resource "time_sleep" "control_plane_rbac" {
  create_duration = "60s"

  depends_on = [azurerm_role_assignment.control_plane_network]
}

resource "azurerm_kubernetes_cluster" "this" {
  # checkov:skip=CKV_AZURE_4:Azure Monitor (Container Insights) wiring is the customer's choice; not in v0.1.
  # checkov:skip=CKV_AZURE_6:API access is restricted with api_server_authorized_ip_ranges; open by default as on AWS (Terraform and Helm need it).
  # checkov:skip=CKV_AZURE_115:Public API endpoint (restrictable); a private cluster needs Terraform inside the VNet. Later option.
  # checkov:skip=CKV_AZURE_116:Azure Policy add-on is the customer's choice.
  # checkov:skip=CKV_AZURE_117:Platform-managed disk encryption in v0.1; a disk encryption set (CMK) is a later option.
  # checkov:skip=CKV_AZURE_226:Managed OS disks (128 GB) as the Azure guide; ephemeral disks depend on the VM size's cache.
  # checkov:skip=CKV_AZURE_227:Encryption at host needs a subscription feature registration; a later option.
  # checkov:skip=CKV_AZURE_172:The Secrets Store CSI driver isn't used: External Secrets syncs Key Vault.
  # checkov:skip=CKV_AZURE_232:One node pool runs system and Plane pods (sized for parity with AWS).
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

  # Workload Identity: pods exchange their ServiceAccount token for an Entra token (the IRSA / Pod
  # Identity equivalent). External Secrets and Plane use it; nothing holds a client secret.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Entra ID authentication, Azure RBAC authorization, no static admin kubeconfig.
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

  # One system-mode pool, without the critical-addons taint, for the system add-ons and Plane.
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

  # Node pools as configured here (no Node Auto Provisioning / Karpenter).
  node_provisioning_profile {
    mode = "Manual"
  }

  # Azure Disk CSI for the in-cluster RabbitMQ and OpenSearch volumes; nothing else.
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
      # Managed by the cluster autoscaler after creation.
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

# Azure RBAC for Kubernetes reaches the API server a few minutes after the assignment; Helm's first
# call fails with 403 before that.
resource "time_sleep" "cluster_rbac" {
  create_duration = "120s"

  depends_on = [azurerm_role_assignment.cluster_admin]
}
