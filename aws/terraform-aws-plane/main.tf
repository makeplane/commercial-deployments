data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  # checkov:skip=CKV_AWS_394:The module takes the first az_count zones by name; zones AWS adds later sort after them, so the set doesn't shift.
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs    = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  region = data.aws_region.current.region

  tags = merge(var.tags, {
    "plane.so/deployment" = var.name
    "managed-by"          = "terraform-aws-plane"
  })
}

module "network" {
  source = "./modules/network"

  name               = var.name
  cidr               = var.vpc_cidr
  azs                = local.azs
  single_nat_gateway = var.single_nat_gateway
  tags               = local.tags
}

module "cluster" {
  source = "./modules/cluster"

  name                         = var.name
  kubernetes_version           = var.kubernetes_version
  vpc_id                       = module.network.vpc_id
  private_subnet_ids           = module.network.private_subnet_ids
  public_access_cidrs          = var.cluster_endpoint_public_access_cidrs
  cluster_admin_principal_arns = var.cluster_admin_principal_arns
  node_group                   = var.node_group
  addon_versions               = var.addon_versions
  tags                         = local.tags
}

module "data" {
  source = "./modules/data"

  name                      = var.name
  domain                    = var.domain
  vpc_id                    = module.network.vpc_id
  private_subnet_ids        = module.network.private_subnet_ids
  allowed_security_group_id = module.cluster.node_security_group_id
  postgres                  = var.postgres
  redis                     = var.redis
  rabbitmq                  = var.rabbitmq
  opensearch                = var.opensearch
  bucket_force_destroy      = var.bucket_force_destroy
  tags                      = local.tags
}

module "addons" {
  source = "./modules/addons"

  name              = var.name
  region            = local.region
  cluster_name      = module.cluster.cluster_name
  vpc_id            = module.network.vpc_id
  vpc_cidr          = var.vpc_cidr
  public_subnet_ids = module.network.public_subnet_ids
  allowed_cidrs     = var.allowed_cidrs
  route53_zone_id   = var.route53_zone_id
  issue_certificate = var.acme_email != null
  secret_arns       = module.data.secret_arns
  kms_key_arn       = module.data.kms_key_arn
  tags              = local.tags

  # Helm releases need the node group and the creator's access entry, not only the control
  # plane. An explicit signal instead of a module-level depends_on, which would defer every
  # data source inside the module and make plans noisy.
  cluster_ready = module.cluster.ready
}

# DNS for the NLB the LB controller creates once Traefik is installed.
module "edge" {
  source = "./modules/edge"

  domain             = var.domain
  route53_zone_id    = var.route53_zone_id
  load_balancer_name = module.addons.load_balancer_name
  addons_ready       = module.addons.ready
}

module "plane" {
  source = "./modules/plane"

  name              = var.name
  region            = local.region
  cluster_name      = module.cluster.cluster_name
  domain            = var.domain
  plane_version     = var.plane_version
  chart_version     = var.chart_version
  vpc_cidr          = var.vpc_cidr
  enable_components = var.enable_components
  tls_secret_name   = var.tls_secret_name
  route53_zone_id   = var.route53_zone_id
  acme_email        = var.acme_email
  acme_server       = var.acme_server
  helm_timeout      = var.helm_timeout
  plane_values      = var.plane_values
  data              = module.data.plane_inputs
  tags              = local.tags

  # The chart's extraObjects need the External Secrets, cert-manager and Traefik CRDs and
  # webhooks; on destroy, Plane must go before Traefik and the LB controller.
  addons_ready = module.addons.ready
}

check "certificate_inputs" {
  assert {
    condition     = var.route53_zone_id == null || var.acme_email != null
    error_message = "acme_email is required when route53_zone_id is set: the module issues the certificate through Let's Encrypt."
  }
}
