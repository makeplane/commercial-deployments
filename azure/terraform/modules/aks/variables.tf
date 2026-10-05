variable "name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the cluster"
  type        = string
}

variable "resource_group_id" {
  description = "ID of the resource group (scope for the control-plane Network Contributor role)"
  type        = string
}

variable "subnet_id" {
  description = "Subnet for the AKS nodes"
  type        = string
}

variable "zones" {
  description = "Availability zones for the node pools"
  type        = list(string)
}

variable "kubernetes_version" {
  description = "Kubernetes version (null = AKS default)"
  type        = string
  default     = null
}

variable "sku_tier" {
  description = "AKS control-plane tier: Free, Standard (uptime SLA) or Premium"
  type        = string
  default     = "Standard"
}

variable "automatic_upgrade_channel" {
  description = "AKS automatic upgrade channel (none, patch, stable, rapid, node-image)"
  type        = string
  default     = "patch"
}

variable "local_account_disabled" {
  description = "Disable the static cluster-admin kubeconfig and require Entra ID"
  type        = bool
  default     = true
}

variable "admin_group_object_ids" {
  description = "Entra ID group object IDs granted cluster-admin"
  type        = list(string)
  default     = []
}

variable "deployer_object_id" {
  description = "Object ID of the identity running Terraform, granted AKS RBAC Cluster Admin (null to skip)"
  type        = string
  default     = null
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the API server (empty = unrestricted)"
  type        = list(string)
  default     = []
}

variable "system_node_vm_size" {
  description = "VM size of the system node pool"
  type        = string
}

variable "system_node_min_count" {
  description = "Minimum nodes in the system pool"
  type        = number
}

variable "system_node_max_count" {
  description = "Maximum nodes in the system pool"
  type        = number
}

variable "workload_node_pool_name" {
  description = "Name of the user node pool (lowercase alphanumeric, max 12 chars)"
  type        = string
}

variable "workload_node_vm_size" {
  description = "VM size of the user node pool"
  type        = string
}

variable "workload_node_min_count" {
  description = "Minimum nodes in the user pool"
  type        = number
}

variable "workload_node_max_count" {
  description = "Maximum nodes in the user pool"
  type        = number
}

variable "node_os_disk_size_gb" {
  description = "OS disk size of every node, in GB"
  type        = number
}

variable "pod_cidr" {
  description = "Overlay CIDR for pod IPs (must not overlap the VNet or service CIDR)"
  type        = string
}

variable "service_cidr" {
  description = "CIDR for Kubernetes Service IPs (must not overlap the VNet or pod CIDR)"
  type        = string
}

variable "dns_service_ip" {
  description = "IP of the cluster DNS Service, inside service_cidr"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
