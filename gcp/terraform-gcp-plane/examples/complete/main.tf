provider "google" {
  project = var.project_id
  region  = var.region
}

# The module has no provider blocks. Helm authenticates with a short-lived token from gke-gcloud-auth-plugin.
provider "helm" {
  kubernetes = {
    host                   = module.plane.cluster_endpoint
    cluster_ca_certificate = base64decode(module.plane.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
    }
  }
}

module "plane" {
  # Registry source once published (name settled at release).
  source = "../../"

  # Every input passed through as is: set values in terraform.tfvars; unset means the module default.
  name                       = var.name
  domain                     = var.domain
  deployment_mode            = var.deployment_mode
  plane_version              = var.plane_version
  chart_version              = var.chart_version
  chart_repository           = var.chart_repository
  chart_name                 = var.chart_name
  acme_email                 = var.acme_email
  acme_server                = var.acme_server
  enable_components          = var.enable_components
  plane_ai                   = var.plane_ai
  labels                     = var.labels
  ingress                    = var.ingress
  tls_secret_name            = var.tls_secret_name
  project_id                 = var.project_id
  region                     = var.region
  zones                      = var.zones
  enable_apis                = var.enable_apis
  network                    = var.network
  master_authorized_networks = var.master_authorized_networks
  cluster_admin_members      = var.cluster_admin_members
  release_channel            = var.release_channel
  node_pool                  = var.node_pool
  helm_timeout               = var.helm_timeout
  plane_values               = var.plane_values
  postgres                   = var.postgres
  redis                      = var.redis
  rabbitmq                   = var.rabbitmq
  opensearch                 = var.opensearch
  email                      = var.email
  use_storage_proxy          = var.use_storage_proxy
  bucket_force_destroy       = var.bucket_force_destroy
}
