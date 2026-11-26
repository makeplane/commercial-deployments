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

variable "vnet_cidr" {
  description = "VNet address space."
  type        = string
}

variable "aks_subnet_cidr" {
  description = "AKS node subnet."
  type        = string
}

variable "postgres_subnet_cidr" {
  description = "Subnet delegated to PostgreSQL Flexible Server."
  type        = string
}

variable "private_endpoints_subnet_cidr" {
  description = "Private endpoints subnet."
  type        = string
}

variable "zones" {
  description = "Availability zones for the NAT public IP."
  type        = list(string)
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}
