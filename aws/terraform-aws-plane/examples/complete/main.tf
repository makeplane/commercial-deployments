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

  name            = var.name
  domain          = var.domain
  route53_zone_id = var.route53_zone_id
  acme_email      = var.acme_email
  acme_server     = var.acme_server

  vpc_cidr = var.vpc_cidr

  opensearch           = { enabled = var.enable_opensearch }
  postgres             = { deletion_protection = var.postgres_deletion_protection }
  bucket_force_destroy = var.bucket_force_destroy

  cluster_endpoint_public_access_cidrs = var.admin_cidrs
  cluster_admin_principal_arns         = var.cluster_admin_principal_arns

  tags = {
    Environment = "example"
  }
}
