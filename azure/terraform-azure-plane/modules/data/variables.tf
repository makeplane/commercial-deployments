variable "name" {
  description = "Name prefix."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group."
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant (Key Vault)."
  type        = string
}

variable "deployer_object_id" {
  description = "Object ID of the identity running Terraform (writes the Key Vault secrets)."
  type        = string
}

variable "vnet_id" {
  description = "VNet ID (private DNS zone links)."
  type        = string
}

variable "postgres_subnet_id" {
  description = "Subnet delegated to PostgreSQL Flexible Server."
  type        = string
}

variable "private_endpoints_subnet_id" {
  description = "Subnet for private endpoints."
  type        = string
}

variable "nat_public_ip" {
  description = "The cluster's egress IP, allowed through the Key Vault firewall when it is on."
  type        = string
}

variable "zones" {
  description = "Availability zones (PostgreSQL primary in the first, standby in the second)."
  type        = list(string)
}

variable "postgres" {
  description = "PostgreSQL Flexible Server settings."
  type = object({
    engine_version               = string
    sku_name                     = string
    storage_mb                   = number
    high_availability_mode       = string
    backup_retention_days        = number
    geo_redundant_backup_enabled = bool
    deletion_protection          = bool
  })
}

variable "redis" {
  description = "Azure Managed Redis settings."
  type = object({
    sku_name                  = string
    high_availability_enabled = bool
    clustering_policy         = string
    persistence               = bool
  })
}

variable "opensearch_enabled" {
  description = "Generate the in-cluster OpenSearch password."
  type        = bool
}

variable "storage" {
  description = "Uploads storage settings."
  type = object({
    replication_type           = string
    container_name             = string
    versioning_enabled         = bool
    soft_delete_retention_days = number
    deletion_protection        = bool
  })
}

variable "key_vault" {
  description = "Key Vault settings."
  type = object({
    purge_protection_enabled   = bool
    soft_delete_retention_days = number
    allowed_ips                = list(string)
    private_endpoint_enabled   = bool
  })
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}
