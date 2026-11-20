provider "azurerm" {
  subscription_id = var.subscription_id
  # The uploads account has no shared keys.
  storage_use_azuread = true

  features {
    key_vault {
      # Purge protection forbids purging; the vault name's random suffix avoids reinstall collisions.
      purge_soft_delete_on_destroy          = false
      purge_soft_deleted_secrets_on_destroy = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

# AKS local accounts are off, so Helm uses kubelogin (CI: --login workloadidentity).
provider "helm" {
  kubernetes = {
    host                   = module.plane.cluster_endpoint
    cluster_ca_certificate = base64decode(module.plane.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "kubelogin"
      # The AKS AAD server app ID, the same for every cluster.
      args = ["get-token", "--login", "azurecli", "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630"]
    }
  }
}

module "plane" {
  # Registry source once published: source = "makeplane/plane/azure", version = "~> 0.1"
  source = "../../"

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
  pi                              = var.pi
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
  use_storage_proxy               = var.use_storage_proxy
  key_vault                       = var.key_vault
  persistent_volume_sku           = var.persistent_volume_sku
}
