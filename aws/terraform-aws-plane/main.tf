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
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  eks    = var.deployment_mode == "eks"
  docker = var.deployment_mode == "docker"

  # Path A: the module serves Plane (EKS: Traefik, Plane's routes and the certificates; Docker: the stack's Caddy
  # proxy). Path B: you bring the ingress. The default depends on the mode.
  ingress      = merge(var.ingress, { mode = coalesce(var.ingress.mode, local.docker ? "automated" : "none") })
  automated    = local.ingress.mode == "automated"
  lets_encrypt = local.automated && var.acme_email != null

  # Docker path A internet-facing: the instance sits in a public subnet with an Elastic IP, so no NAT gateway.
  docker_public = local.docker && local.automated && var.ingress.scheme == "internet-facing"

  # Plane's email intake domain: a subdomain, so its MX record never collides with a CNAME on domain.
  # No load balancer without the email service.
  email = merge(var.email, {
    smtp_domain   = coalesce(var.email.smtp_domain, "intake.${var.domain}")
    load_balancer = var.email.enabled && var.email.load_balancer
  })
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
  enable_nat_gateway = !local.docker_public
  tags               = local.tags
}

################################################################################
# EKS mode
################################################################################

module "cluster" {
  source = "./modules/cluster"
  count  = local.eks ? 1 : 0

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
  count  = local.eks ? 1 : 0

  name                      = var.name
  domain                    = var.domain
  vpc_id                    = module.network.vpc_id
  private_subnet_ids        = module.network.private_subnet_ids
  allowed_security_group_id = module.cluster[0].node_security_group_id
  postgres                  = var.postgres
  redis                     = var.redis
  rabbitmq                  = var.rabbitmq
  opensearch                = var.opensearch
  bucket_force_destroy      = var.bucket_force_destroy
  tags                      = local.tags
}

module "addons" {
  source = "./modules/addons"
  count  = local.eks ? 1 : 0

  name                 = var.name
  region               = local.region
  cluster_name         = module.cluster[0].cluster_name
  vpc_id               = module.network.vpc_id
  vpc_cidr             = var.vpc_cidr
  public_subnet_ids    = module.network.public_subnet_ids
  private_subnet_ids   = module.network.private_subnet_ids
  install_traefik      = local.automated
  allowed_cidrs        = var.ingress.allowed_cidrs
  load_balancer_scheme = var.ingress.scheme
  issue_certificate    = local.lets_encrypt
  certificate_secret_arns = compact([
    local.automated ? var.ingress.tls_certificate_secret_arn : null,
    local.email.enabled ? local.email.certificate_secret_arn : null,
  ])
  secret_arns = module.data[0].secret_arns
  kms_key_arn = module.data[0].kms_key_arn
  tags        = local.tags

  # Helm releases need the node group and the creator's access entry, not only the control
  # plane. An explicit signal instead of a module-level depends_on, which would defer every
  # data source inside the module and make plans noisy.
  cluster_ready = module.cluster[0].ready
}

# The NLB in front of the module's Traefik (path A). The module creates no DNS records.
module "edge" {
  source = "./modules/edge"
  count  = local.eks ? 1 : 0

  install_traefik    = local.automated
  load_balancer_name = module.addons[0].load_balancer_name
  addons_ready       = module.addons[0].ready
}

module "plane" {
  source = "./modules/plane"
  count  = local.eks ? 1 : 0

  name              = var.name
  region            = local.region
  cluster_name      = module.cluster[0].cluster_name
  domain            = var.domain
  plane_version     = var.plane_version
  chart_version     = var.chart_version
  vpc_cidr          = var.vpc_cidr
  enable_components = var.enable_components
  tls_secret_name   = var.tls_secret_name
  email             = local.email
  public_subnet_ids = module.network.public_subnet_ids
  chart_repository  = var.chart_repository
  chart_name        = var.chart_name
  ingress_enabled   = local.automated
  acme_email        = local.lets_encrypt ? var.acme_email : null
  acme_server       = var.acme_server

  tls_certificate_secret_arn = var.ingress.tls_certificate_secret_arn
  helm_timeout               = var.helm_timeout
  plane_values               = var.plane_values
  data                       = module.data[0].plane_inputs
  tags                       = local.tags

  # The chart's extraObjects need the External Secrets, cert-manager and Traefik CRDs and
  # webhooks; on destroy, Plane must go before Traefik and the LB controller.
  addons_ready = module.addons[0].ready
}

# The EKS submodules gained count (Docker mode); existing EKS installs keep every resource.
moved {
  from = module.cluster
  to   = module.cluster[0]
}

moved {
  from = module.data
  to   = module.data[0]
}

moved {
  from = module.addons
  to   = module.addons[0]
}

moved {
  from = module.edge
  to   = module.edge[0]
}

moved {
  from = module.plane
  to   = module.plane[0]
}

################################################################################
# Docker mode
################################################################################

module "docker" {
  source = "./modules/docker"
  count  = local.docker ? 1 : 0

  name          = var.name
  domain        = var.domain
  plane_version = var.plane_version
  vpc_id        = module.network.vpc_id
  vpc_cidr      = var.vpc_cidr
  # Path A internet-facing: a public subnet (Elastic IP). Internal and path B: a private one.
  subnet_id         = local.docker_public ? module.network.public_subnet_ids[0] : module.network.private_subnet_ids[0]
  availability_zone = local.azs[0]

  ingress              = local.ingress
  acme_email           = local.lets_encrypt ? var.acme_email : null
  acme_server          = var.acme_server
  email                = local.email
  enable_components    = var.enable_components
  docker               = var.docker
  bucket_force_destroy = var.bucket_force_destroy
  tags                 = local.tags
}

# Path A without an email certificate still works (the email app self-signs, fine for receiving
# mail); ask for one without blocking the apply.
check "email_certificate" {
  assert {
    condition     = !local.automated || !local.email.enabled || !local.email.load_balancer || local.email.certificate_secret_arn != null
    error_message = "No email certificate (email.certificate_secret_arn): the email service uses a self-signed one. That's fine for receiving mail; store a certificate in Secrets Manager and set email.certificate_secret_arn for a trusted one."
  }
}
