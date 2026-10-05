output "resource_group_name" {
  description = "Resource group holding every resource"
  value       = local.resource_group_name
}

output "tenant_id" {
  description = "Entra ID tenant (SecretStore spec.provider.azurekv.tenantId)"
  value       = data.azurerm_client_config.current.tenant_id
}

output "vnet_id" {
  description = "ID of the VNet"
  value       = module.network.vnet_id
}

output "aks_subnet_id" {
  description = "ID of the AKS node subnet"
  value       = module.network.aks_subnet_id
}

output "nat_public_ip" {
  description = "Egress public IP of the cluster (allow-list this on external services)"
  value       = module.network.nat_public_ip
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "aks_node_resource_group" {
  description = "Resource group AKS manages for nodes, disks and its load balancer"
  value       = module.aks.node_resource_group
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster"
  value       = module.aks.oidc_issuer_url
}

output "configure_kubectl" {
  description = "Command to configure kubectl for the cluster (requires kubelogin)"
  value       = "az aks get-credentials --resource-group ${local.resource_group_name} --name ${module.aks.cluster_name} && kubelogin convert-kubeconfig -l azurecli"
}

output "postgres_fqdn" {
  description = "Private FQDN of PostgreSQL (env.pgdb_host)"
  value       = module.postgres.fqdn
}

output "postgres_database_names" {
  description = "Databases created on PostgreSQL"
  value       = module.postgres.database_names
}

output "redis_hostname" {
  description = "Redis hostname (env.redis_host)"
  value       = module.redis.hostname
}

output "redis_port" {
  description = "Redis TLS port (env.redis_port)"
  value       = module.redis.port
}

output "storage_account_name" {
  description = "Storage account for Plane uploads"
  value       = module.object_store.storage_account_name
}

output "storage_blob_endpoint" {
  description = "Blob service endpoint"
  value       = module.object_store.blob_endpoint
}

output "storage_container_name" {
  description = "Blob container for Plane uploads"
  value       = module.object_store.container_name
}

output "key_vault_name" {
  description = "Name of the Key Vault holding the generated credentials"
  value       = module.key_vault.name
}

output "key_vault_uri" {
  description = "Key Vault URI (SecretStore spec.provider.azurekv.vaultUrl)"
  value       = module.key_vault.vault_uri
}

output "key_vault_secret_names" {
  description = "Secrets stored in Key Vault"
  value       = module.key_vault.secret_names
}

output "plane_workload_identity_client_id" {
  description = "Client ID for the Plane ServiceAccount annotation azure.workload.identity/client-id"
  value       = module.identity.plane_client_id
}

output "keyvault_reader_identity_client_id" {
  description = "Client ID for the SecretStore ServiceAccount annotation azure.workload.identity/client-id"
  value       = module.identity.eso_client_id
}

output "ingress_public_ip" {
  description = "Public IP for the ingress controller — point your Plane DNS record here"
  value       = module.public_ips.ingress_ip
}

output "ingress_public_ip_name" {
  description = "Name of the ingress public IP (service.beta.kubernetes.io/azure-pip-name)"
  value       = module.public_ips.ingress_ip_name
}

output "ingress_fqdn" {
  description = "<label>.<region>.cloudapp.azure.com when ingress_domain_name_label is set"
  value       = module.public_ips.ingress_fqdn
}

output "email_public_ip" {
  description = "Public IP for inbound email — use it in the MX record. Null when enable_email_public_ip = false."
  value       = module.public_ips.email_ip
}

output "email_public_ip_name" {
  description = "Name of the email public IP (service.beta.kubernetes.io/azure-pip-name)"
  value       = module.public_ips.email_ip_name
}

output "helm_values" {
  description = "plane-enterprise values derived from this infrastructure; merge with azure/examples/values-azure.yaml"
  value = yamlencode({
    serviceAccount = {
      annotations = { "azure.workload.identity/client-id" = module.identity.plane_client_id }
      podLabels   = { "azure.workload.identity/use" = "true" }
    }
    env = {
      # Object-storage settings are deliberately absent: they live in
      # values-azure.yaml, which defaults to the bundled MinIO until Plane ships
      # its native Azure Blob provider.
      storageClass  = "managed-csi-premium"
      pgdb_host     = module.postgres.fqdn
      pgdb_port     = tostring(module.postgres.port)
      pgdb_name     = var.postgres.database_names[0]
      pg_pi_db_name = try(var.postgres.database_names[1], "plane_pi")
      redis_host    = module.redis.hostname
      redis_port    = tostring(module.redis.port)
      redis_ssl     = true
    }
  })
}
