variable "name" {
  description = "Name prefix for the private endpoint and DNS link"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the storage account"
  type        = string
}

variable "vnet_id" {
  description = "VNet to link the privatelink.blob DNS zone to"
  type        = string
}

variable "private_endpoints_subnet_id" {
  description = "Subnet for the Blob private endpoint"
  type        = string
}

variable "account_name_prefix" {
  description = "Prefix of the storage account name (a random suffix is appended)"
  type        = string
}

variable "replication_type" {
  description = "LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS"
  type        = string
}

variable "container_name" {
  description = "Blob container that holds Plane uploads"
  type        = string
}

variable "versioning_enabled" {
  description = "Keep previous versions of overwritten blobs"
  type        = bool
}

variable "soft_delete_retention_days" {
  description = "Days deleted blobs and containers can be recovered"
  type        = number
}

variable "public_network_access_enabled" {
  description = "Expose the Blob endpoint publicly (only needed for direct browser uploads)"
  type        = bool
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
