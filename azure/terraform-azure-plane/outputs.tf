locals {
  load_balancer_ip       = local.automated ? (local.internal ? local.internal_ingress_ip : module.edge.ingress_public_ip) : null
  email_load_balancer_ip = local.email.load_balancer ? module.edge.email_public_ip : null
}

output "plane_url" {
  description = "URL Plane is served on."
  value       = "https://${var.domain}"
}

output "deployment_mode" {
  description = "Deployment mode in use."
  value       = var.deployment_mode
}

output "load_balancer_ip" {
  description = "Path A: address of the load balancer in front of Traefik (null in path B): a static public IP, or with ingress.scheme = \"internal\" a fixed private IP in the AKS subnet. Point domain here with an A record."
  value       = local.load_balancer_ip
}

output "email_load_balancer_ip" {
  description = "Static public IP of the email load balancer (null without email.load_balancer). email.smtp_domain's A record points here."
  value       = local.email_load_balancer_ip
}

output "dns_records" {
  description = "The DNS records to create (the module creates none). web: path A only; in path B, point domain at your own ingress load balancer. An MX record can't point at an IP, so with the email load balancer smtp_domain gets an A record (email_host) and an MX record naming it (email_mx)."
  value = {
    web = local.load_balancer_ip == null ? null : {
      name  = var.domain
      type  = "A (DNS-only, no proxy)"
      value = local.load_balancer_ip
    }
    email_host = local.email_load_balancer_ip == null ? null : {
      name  = local.email.smtp_domain
      type  = "A (DNS-only, no proxy)"
      value = local.email_load_balancer_ip
    }
    email_mx = local.email_load_balancer_ip == null ? null : {
      name  = local.email.smtp_domain
      type  = "MX"
      value = "10 ${local.email.smtp_domain}"
    }
  }
}

output "resource_group_name" {
  description = "Resource group holding the deployment."
  value       = local.resource_group_name
}

output "vnet_id" {
  description = "VNet ID."
  value       = module.network.vnet_id
}

output "aks_subnet_id" {
  description = "AKS node subnet ID."
  value       = module.network.aks_subnet_id
}

output "nat_public_ip" {
  description = "Egress IP of the cluster (NAT gateway). Allow-list it where Plane calls out (SMTP relays, identity providers, webhooks)."
  value       = module.network.nat_public_ip
}

output "cluster_name" {
  description = "AKS cluster name."
  value       = module.cluster.cluster_name
}

output "cluster_endpoint" {
  description = "AKS API endpoint."
  value       = module.cluster.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "AKS cluster CA (base64)."
  value       = module.cluster.cluster_certificate_authority_data
}

output "configure_kubectl" {
  description = "Command to point kubectl at the cluster (Entra ID through kubelogin; local accounts are off)."
  value       = "az aks get-credentials --resource-group ${local.resource_group_name} --name ${module.cluster.cluster_name} && kubelogin convert-kubeconfig -l azurecli"
}

output "postgres_endpoint" {
  description = "PostgreSQL Flexible Server FQDN (private, resolves inside the VNet)."
  value       = module.data.postgres_host
}

output "redis_endpoint" {
  description = "Azure Managed Redis endpoint (host:port; TLS, private endpoint)."
  value       = "${module.data.plane_inputs.redis_host}:${module.data.plane_inputs.redis_port}"
}

output "rabbitmq_endpoint" {
  description = "In-cluster RabbitMQ Service (AMQP, port 5672)."
  value       = module.plane.rabbitmq_host
}

output "storage_account_name" {
  description = "Storage account for uploads (Blob)."
  value       = module.data.storage_account_name
}

output "storage_container_name" {
  description = "Blob container for uploads."
  value       = module.data.storage_container_name
}

output "tenant_id" {
  description = "Entra ID tenant."
  value       = data.azurerm_client_config.current.tenant_id
}

output "key_vault_uri" {
  description = "URI of the Key Vault holding the generated secrets."
  value       = module.data.key_vault_uri
}

output "key_vault_secret_ids" {
  description = "Versionless IDs of the Key Vault secrets the deployment uses (IDs only, never values)."
  value       = module.data.secret_ids
}

output "external_secrets_client_id" {
  description = "Client ID of the managed identity External Secrets uses to read Key Vault (Workload Identity)."
  value       = module.addons.external_secrets_client_id
}

output "plane_identity_client_id" {
  description = "Client ID of the managed identity Plane's pods use for Blob Storage (Workload Identity)."
  value       = module.plane.identity_client_id
}

output "plane_helm_values" {
  description = "The plane-enterprise chart values the module generates from the infrastructure (YAML): endpoints, storage account, domain, load balancer and Secret names; no secret values. Excludes plane_values. For support, debugging and reading what was installed."
  value       = module.plane.helm_values
}
