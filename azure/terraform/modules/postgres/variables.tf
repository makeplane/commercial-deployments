variable "name" {
  description = "Name prefix for the PostgreSQL resources"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the server"
  type        = string
}

variable "vnet_id" {
  description = "VNet to link the private DNS zone to"
  type        = string
}

variable "subnet_id" {
  description = "Subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL major version"
  type        = string
}

variable "sku_name" {
  description = "Compute SKU, e.g. GP_Standard_D4ds_v5"
  type        = string
}

variable "storage_mb" {
  description = "Initial storage in MB (auto-grow is enabled)"
  type        = number
}

variable "zone" {
  description = "Availability zone of the primary server"
  type        = string
  default     = "1"
}

variable "standby_zone" {
  description = "Availability zone of the standby when high_availability_mode is ZoneRedundant"
  type        = string
  default     = "2"
}

variable "high_availability_mode" {
  description = "ZoneRedundant, SameZone or Disabled"
  type        = string

  validation {
    condition     = contains(["ZoneRedundant", "SameZone", "Disabled"], var.high_availability_mode)
    error_message = "high_availability_mode must be ZoneRedundant, SameZone or Disabled."
  }
}

variable "backup_retention_days" {
  description = "Point-in-time restore retention, 7-35 days"
  type        = number
}

variable "geo_redundant_backup_enabled" {
  description = "Store backups in the paired region (cannot be changed after creation)"
  type        = bool
}

variable "administrator_login" {
  description = "Administrator username"
  type        = string
}

variable "administrator_password" {
  description = "Administrator password"
  type        = string
  sensitive   = true
}

variable "database_names" {
  description = "Databases to create on the server"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
