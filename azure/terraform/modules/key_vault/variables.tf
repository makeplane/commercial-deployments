variable "name" {
  description = "Name prefix for the Key Vault (a random suffix is appended)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the Key Vault"
  type        = string
}

variable "vnet_id" {
  description = "VNet to link the privatelink.vaultcore DNS zone to (private endpoint only)"
  type        = string
}

variable "private_endpoints_subnet_id" {
  description = "Subnet for the Key Vault private endpoint (private endpoint only)"
  type        = string
}

variable "purge_protection_enabled" {
  description = "Prevent permanent deletion during the soft-delete retention period"
  type        = bool
}

variable "soft_delete_retention_days" {
  description = "Days a deleted vault or secret can be recovered (7-90)"
  type        = number
}

variable "public_network_access_enabled" {
  description = "Allow access over the public endpoint (subject to network_acls)"
  type        = bool
}

variable "allowed_ips" {
  description = "Public IPs/CIDRs allowed through the vault firewall. Empty = no firewall."
  type        = list(string)
}

variable "extra_allowed_ips" {
  description = "Additional IPs allowed when the firewall is on (e.g. the AKS NAT egress IP)"
  type        = list(string)
  default     = []
}

variable "private_endpoint_enabled" {
  description = "Create a private endpoint for the vault"
  type        = bool
}

variable "secret_names" {
  description = "Names of the secrets to create (keys of secret_values)"
  type        = list(string)
}

variable "secret_values" {
  description = "Secret values keyed by secret name"
  type        = map(string)
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
