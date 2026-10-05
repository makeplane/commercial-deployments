variable "name" {
  description = "Name prefix for network resources"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create the network in"
  type        = string
}

variable "vnet_cidr" {
  description = "Address space of the virtual network"
  type        = string
}

variable "aks_subnet_cidr" {
  description = "CIDR of the AKS node subnet"
  type        = string
}

variable "postgres_subnet_cidr" {
  description = "CIDR of the subnet delegated to PostgreSQL Flexible Server"
  type        = string
}

variable "private_endpoints_subnet_cidr" {
  description = "CIDR of the subnet that holds private endpoints"
  type        = string
}

variable "zones" {
  description = "Availability zones for the NAT gateway public IP"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
