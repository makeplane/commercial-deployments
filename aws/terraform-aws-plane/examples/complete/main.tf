provider "aws" {
  region = var.region
}

# The module has no provider blocks. Helm talks to the cluster the module creates, with a
# short-lived token from the AWS CLI (no static credentials).
provider "helm" {
  kubernetes = {
    host                   = module.plane.cluster_endpoint
    cluster_ca_certificate = base64decode(module.plane.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.plane.cluster_name, "--region", var.region]
    }
  }
}

module "plane" {
  # Registry source once published: source = "makeplane/plane/aws", version = "~> 0.1"
  source = "../../"

  # Every input passed through as is: set values in terraform.tfvars; unset means the module default.
  name                                 = var.name
  domain                               = var.domain
  deployment_mode                      = var.deployment_mode
  plane_version                        = var.plane_version
  chart_version                        = var.chart_version
  chart_repository                     = var.chart_repository
  chart_name                           = var.chart_name
  acme_email                           = var.acme_email
  acme_server                          = var.acme_server
  allowed_cidrs                        = var.allowed_cidrs
  enable_components                    = var.enable_components
  tags                                 = var.tags
  route53_zone_id                      = var.route53_zone_id
  tls_secret_name                      = var.tls_secret_name
  vpc_cidr                             = var.vpc_cidr
  az_count                             = var.az_count
  single_nat_gateway                   = var.single_nat_gateway
  kubernetes_version                   = var.kubernetes_version
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  cluster_admin_principal_arns         = var.cluster_admin_principal_arns
  node_group                           = var.node_group
  addon_versions                       = var.addon_versions
  helm_timeout                         = var.helm_timeout
  plane_values                         = var.plane_values
  postgres                             = var.postgres
  redis                                = var.redis
  rabbitmq                             = var.rabbitmq
  opensearch                           = var.opensearch
  email                                = var.email
  bucket_force_destroy                 = var.bucket_force_destroy
}
