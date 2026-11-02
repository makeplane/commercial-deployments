locals {
  # Path A: the module installs Traefik, Plane's routes and the certificates. Path B: none of them.
  automated    = var.ingress.mode == "automated"
  lets_encrypt = local.automated && var.acme_email != null

  # Plane's email intake domain: a subdomain, so its A and MX records never collide with your records on domain.
  # No load balancer without the email service.
  email = merge(var.email, {
    smtp_domain   = coalesce(var.email.smtp_domain, "intake.${var.domain}")
    load_balancer = var.email.enabled && var.email.load_balancer
  })

  labels = merge(var.labels, {
    "plane-deployment" = var.name
    "managed-by"       = "terraform-gcp-plane"
  })
}

# The network module also enables the project APIs. Every other module takes project_id from it, so nothing is
# created before its API is on.
module "network" {
  source = "./modules/network"

  name        = var.name
  project_id  = var.project_id
  region      = var.region
  enable_apis = var.enable_apis
  network     = var.network
}

module "cluster" {
  source = "./modules/cluster"

  name                       = var.name
  project_id                 = module.network.project_id
  region                     = var.region
  zones                      = var.zones
  network_id                 = module.network.network_id
  subnet_id                  = module.network.subnet_id
  pods_range_name            = module.network.pods_range_name
  services_range_name        = module.network.services_range_name
  master_authorized_networks = var.master_authorized_networks
  cluster_admin_members      = var.cluster_admin_members
  release_channel            = var.release_channel
  node_pool                  = var.node_pool
  labels                     = local.labels
}

module "data" {
  source = "./modules/data"

  name                  = var.name
  project_id            = module.network.project_id
  region                = var.region
  domain                = var.domain
  network_id            = module.network.network_id
  private_service_range = module.network.private_service_range_name
  postgres              = var.postgres
  redis                 = var.redis
  opensearch            = var.opensearch
  bucket_force_destroy  = var.bucket_force_destroy
  labels                = local.labels
}

# Reserved static IPs for the load balancers GKE creates for Traefik (path A) and the email service. Reserved before
# the add-ons and Plane, so the IPs (and dns_records) never change with the Services. The module creates no DNS records.
module "edge" {
  source = "./modules/edge"

  name                = var.name
  project_id          = module.network.project_id
  region              = var.region
  subnet_id           = module.network.subnet_id
  install_traefik     = local.automated
  web_scheme          = var.ingress.scheme
  email_load_balancer = local.email.load_balancer
  labels              = local.labels
}

module "addons" {
  source = "./modules/addons"

  name                 = var.name
  project_id           = module.network.project_id
  install_traefik      = local.automated
  allowed_cidrs        = var.ingress.allowed_cidrs
  load_balancer_scheme = var.ingress.scheme
  web_address_name     = module.edge.web_address_name
  issue_certificate    = local.lets_encrypt
  certificate_secrets = compact([
    local.automated ? var.ingress.tls_certificate_secret : null,
    local.email.enabled ? local.email.certificate_secret : null,
  ])
  secret_ids = module.data.secret_ids

  # Helm releases need the node pool, not only the control plane. An explicit signal instead of a module-level
  # depends_on, which would defer every data source inside the module and make plans noisy.
  cluster_ready = module.cluster.ready
}

module "plane" {
  source = "./modules/plane"

  name               = var.name
  project_id         = module.network.project_id
  domain             = var.domain
  plane_version      = var.plane_version
  chart_version      = var.chart_version
  pods_cidr          = var.network.pods_cidr
  enable_components  = var.enable_components
  tls_secret_name    = var.tls_secret_name
  email              = local.email
  email_address_name = module.edge.email_address_name
  chart_repository   = var.chart_repository
  chart_name         = var.chart_name
  ingress_enabled    = local.automated
  acme_email         = local.lets_encrypt ? var.acme_email : null
  acme_server        = var.acme_server
  use_storage_proxy  = var.use_storage_proxy
  rabbitmq           = var.rabbitmq
  opensearch         = var.opensearch

  tls_certificate_secret = var.ingress.tls_certificate_secret
  helm_timeout           = var.helm_timeout
  plane_values           = var.plane_values
  data                   = module.data.plane_inputs

  # The chart's extraObjects need the External Secrets and cert-manager CRDs and webhooks; on destroy, Plane must go
  # before Traefik and the add-ons.
  addons_ready = module.addons.ready
}

# Path A without an email certificate still works (the email app self-signs, fine for receiving mail); ask for one
# without blocking the apply.
check "email_certificate" {
  assert {
    condition     = !local.automated || !local.email.enabled || !local.email.load_balancer || local.email.certificate_secret != null
    error_message = "No email certificate (email.certificate_secret): the email service uses a self-signed one. That's fine for receiving mail; store a certificate in Secret Manager and set email.certificate_secret for a trusted one."
  }
}
