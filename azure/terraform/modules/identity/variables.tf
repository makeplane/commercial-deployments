variable "name" {
  description = "Name prefix for the identities"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the identities"
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL of the AKS cluster"
  type        = string
}

variable "plane_namespace" {
  description = "Namespace Plane is installed into"
  type        = string
}

variable "plane_service_account" {
  description = "ServiceAccount used by the Plane workloads"
  type        = string
}

variable "eso_namespace" {
  description = "Namespace External Secrets Operator is installed into"
  type        = string
}

variable "eso_service_account" {
  description = "ServiceAccount the External Secrets SecretStore authenticates as"
  type        = string
}

variable "storage_account_id" {
  description = "Storage account the Plane identity may read and write"
  type        = string
}

variable "key_vault_id" {
  description = "Key Vault the External Secrets identity may read"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
