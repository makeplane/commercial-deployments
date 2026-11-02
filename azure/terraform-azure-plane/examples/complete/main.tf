provider "azurerm" {
  subscription_id = var.subscription_id
  # The uploads account has no shared keys: any storage data-plane call uses Entra ID.
  storage_use_azuread = true

  features {
    key_vault {
      # Purge protection (default) forbids purging: leave the destroyed vault and its secrets
      # soft-deleted instead of failing the destroy. The vault name carries a random suffix, so a
      # reinstall doesn't collide with it.
      purge_soft_delete_on_destroy          = false
      purge_soft_deleted_secrets_on_destroy = false
    }
    resource_group {
      # Never delete a resource group that still holds resources Terraform doesn't know about.
      prevent_deletion_if_contains_resources = true
    }
  }
}

# The module has no provider blocks. AKS has local accounts off (Entra ID only), so Helm authenticates
# through kubelogin with the Azure CLI login (CI: --login workloadidentity, or azurecli after azure/login).
provider "helm" {
  kubernetes = {
    host                   = module.plane.cluster_endpoint
    cluster_ca_certificate = base64decode(module.plane.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "kubelogin"
      # The AKS AAD server application ID (the same for every cluster).
      args = ["get-token", "--login", "azurecli", "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630"]
    }
  }
}

module "plane" {
  # Registry source once published: source = "makeplane/plane/azurerm", version = "~> 0.1"
  source = "../../"

  # Every input passed through as is: set values in terraform.tfvars; unset means the module default.
  name                            = var.name
  domain                          = var.domain
  deployment_mode                 = var.deployment_mode
  plane_version                   = var.plane_version
  chart_version                   = var.chart_version
  chart_repository                = var.chart_repository
  chart_name                      = var.chart_name
  acme_email                      = var.acme_email
  acme_server                     = var.acme_server
  enable_components               = var.enable_components
  tags                            = var.tags
  ingress                         = var.ingress
  tls_secret_name                 = var.tls_secret_name
  email                           = var.email
  location                        = var.location
  resource_group                  = var.resource_group
  vnet_cidr                       = var.vnet_cidr
  zones                           = var.zones
  kubernetes_version              = var.kubernetes_version
  api_server_authorized_ip_ranges = var.api_server_authorized_ip_ranges
  cluster_admin_object_ids        = var.cluster_admin_object_ids
  node_pool                       = var.node_pool
  helm_timeout                    = var.helm_timeout
  plane_values                    = var.plane_values
  postgres                        = var.postgres
  redis                           = var.redis
  rabbitmq                        = var.rabbitmq
  opensearch                      = var.opensearch
  storage                         = var.storage
  key_vault                       = var.key_vault
  persistent_volume_sku           = var.persistent_volume_sku
}
