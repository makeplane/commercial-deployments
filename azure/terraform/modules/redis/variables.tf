variable "name" {
  description = "Name prefix for the Redis resources"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for Redis"
  type        = string
}

variable "vnet_id" {
  description = "VNet to link the private DNS zone to"
  type        = string
}

variable "private_endpoints_subnet_id" {
  description = "Subnet for the Redis private endpoint"
  type        = string
}

variable "sku_name" {
  description = "Azure Managed Redis SKU, e.g. Balanced_B1"
  type        = string
}

variable "high_availability_enabled" {
  description = "Replicate data across a second node"
  type        = bool
}

variable "clustering_policy" {
  description = "NoCluster, EnterpriseCluster or OSSCluster. Plane's clients are not cluster-aware, so OSSCluster is not supported."
  type        = string

  validation {
    condition     = contains(["NoCluster", "EnterpriseCluster"], var.clustering_policy)
    error_message = "clustering_policy must be NoCluster or EnterpriseCluster (Plane's Redis clients are not cluster-aware)."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
