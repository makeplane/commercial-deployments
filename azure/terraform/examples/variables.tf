variable "name" {
  description = "Name of the deployment; prefixes every resource and names the AKS cluster"
  type        = string
  default     = "plane-aks"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "name must be 3-32 chars of lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "location" {
  description = "Azure region for all resources, e.g. eastus2. Must support availability zones."
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID (null = ARM_SUBSCRIPTION_ID or the Azure CLI default)"
  type        = string
  default     = null
}

variable "vnet_cidr" {
  description = "Address space of the VNet. Subnets are carved from it: /20 for AKS nodes, /24 for PostgreSQL, /24 for private endpoints."
  type        = string
  default     = "10.0.0.0/16"
}

variable "zones" {
  description = "Availability zones to spread nodes and zone-redundant resources across"
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version (null = the AKS default version)"
  type        = string
  default     = null
}

variable "ingress_domain_name_label" {
  description = "Optional DNS label for the ingress IP: <label>.<location>.cloudapp.azure.com"
  type        = string
  default     = null
}

variable "enable_email_public_ip" {
  description = "Create a static public IP for the inbound email service (ports 25/465/587)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

variable "aks" {
  description = "AKS cluster configuration"
  type = object({
    sku_tier                        = string
    system_node_vm_size             = string
    system_node_min_count           = number
    system_node_max_count           = number
    workload_node_pool_name         = string
    workload_node_vm_size           = string
    workload_node_min_count         = number
    workload_node_max_count         = number
    node_os_disk_size_gb            = number
    admin_group_object_ids          = list(string)
    api_server_authorized_ip_ranges = list(string)
    local_account_disabled          = bool
    pod_cidr                        = string
    service_cidr                    = string
    dns_service_ip                  = string
  })
  default = {
    sku_tier                        = "Standard"
    system_node_vm_size             = "Standard_D4ds_v5"
    system_node_min_count           = 2
    system_node_max_count           = 3
    workload_node_pool_name         = "plane"
    workload_node_vm_size           = "Standard_D4ds_v5"
    workload_node_min_count         = 3
    workload_node_max_count         = 6
    node_os_disk_size_gb            = 128
    admin_group_object_ids          = []
    api_server_authorized_ip_ranges = []
    local_account_disabled          = true
    pod_cidr                        = "192.168.0.0/16"
    service_cidr                    = "172.16.0.0/16"
    dns_service_ip                  = "172.16.0.10"
  }
}

variable "postgres" {
  description = "Azure Database for PostgreSQL Flexible Server configuration"
  type = object({
    engine_version               = string
    sku_name                     = string
    storage_mb                   = number
    high_availability_mode       = string
    backup_retention_days        = number
    geo_redundant_backup_enabled = bool
    administrator_login          = string
    database_names               = list(string)
  })
  default = {
    engine_version               = "16"
    sku_name                     = "GP_Standard_D4ds_v5"
    storage_mb                   = 131072
    high_availability_mode       = "ZoneRedundant"
    backup_retention_days        = 14
    geo_redundant_backup_enabled = false
    administrator_login          = "planeadmin"
    database_names               = ["plane", "plane_pi"]
  }
}

variable "redis" {
  description = "Azure Managed Redis configuration"
  type = object({
    sku_name                  = string
    high_availability_enabled = bool
    clustering_policy         = string
  })
  default = {
    sku_name                  = "Balanced_B1"
    high_availability_enabled = true
    clustering_policy         = "NoCluster"
  }
}

variable "object_store" {
  description = "Blob storage configuration"
  type = object({
    account_name_prefix           = string
    replication_type              = string
    container_name                = string
    versioning_enabled            = bool
    soft_delete_retention_days    = number
    public_network_access_enabled = bool
  })
  default = {
    account_name_prefix           = "plane"
    replication_type              = "ZRS"
    container_name                = "uploads"
    versioning_enabled            = false
    soft_delete_retention_days    = 7
    public_network_access_enabled = false
  }
}

variable "key_vault" {
  description = "Key Vault configuration. allowed_ips must include the address Terraform runs from when the firewall is on."
  type = object({
    allowed_ips                   = list(string)
    public_network_access_enabled = bool
    private_endpoint_enabled      = bool
    purge_protection_enabled      = bool
    soft_delete_retention_days    = number
  })
  default = {
    allowed_ips                   = []
    public_network_access_enabled = true
    private_endpoint_enabled      = false
    purge_protection_enabled      = true
    soft_delete_retention_days    = 30
  }
}
