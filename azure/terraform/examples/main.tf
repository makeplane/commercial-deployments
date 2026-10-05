terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}

module "plane_infra" {
  source = "./.."

  name                      = var.name
  location                  = var.location
  subscription_id           = var.subscription_id
  vnet_cidr                 = var.vnet_cidr
  zones                     = var.zones
  kubernetes_version        = var.kubernetes_version
  ingress_domain_name_label = var.ingress_domain_name_label
  enable_email_public_ip    = var.enable_email_public_ip
  tags                      = var.tags

  aks          = var.aks
  postgres     = var.postgres
  redis        = var.redis
  object_store = var.object_store
  key_vault    = var.key_vault
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = module.plane_infra.configure_kubectl
}

output "resource_group_name" {
  description = "Resource group"
  value       = module.plane_infra.resource_group_name
}

output "tenant_id" {
  description = "Entra ID tenant"
  value       = module.plane_infra.tenant_id
}

output "postgres_fqdn" {
  description = "PostgreSQL private FQDN"
  value       = module.plane_infra.postgres_fqdn
}

output "redis_hostname" {
  description = "Redis hostname"
  value       = module.plane_infra.redis_hostname
}

output "storage_account_name" {
  description = "Storage account for uploads"
  value       = module.plane_infra.storage_account_name
}

output "key_vault_name" {
  description = "Key Vault name"
  value       = module.plane_infra.key_vault_name
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = module.plane_infra.key_vault_uri
}

output "plane_workload_identity_client_id" {
  description = "Client ID for the Plane ServiceAccount"
  value       = module.plane_infra.plane_workload_identity_client_id
}

output "keyvault_reader_identity_client_id" {
  description = "Client ID for the SecretStore ServiceAccount"
  value       = module.plane_infra.keyvault_reader_identity_client_id
}

output "ingress_public_ip" {
  description = "Ingress public IP"
  value       = module.plane_infra.ingress_public_ip
}

output "ingress_public_ip_name" {
  description = "Ingress public IP name"
  value       = module.plane_infra.ingress_public_ip_name
}

output "email_public_ip" {
  description = "Email public IP"
  value       = module.plane_infra.email_public_ip
}

output "helm_values" {
  description = "plane-enterprise values derived from this infrastructure"
  value       = module.plane_infra.helm_values
}
