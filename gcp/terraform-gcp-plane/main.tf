locals {
  # Path A: the module installs Traefik, Plane's routes and the certificates. Path B: none of them.
  automated    = var.ingress.mode == "automated"
  lets_encrypt = local.automated && var.acme_email != null

  # A subdomain, so its A and MX records never collide with the customer's records on domain.
  email = merge(var.email, {
    smtp_domain   = coalesce(var.email.smtp_domain, "intake.${var.domain}")
    load_balancer = var.email.enabled && var.email.load_balancer
  })

  labels = merge(var.labels, {
    "plane-deployment" = var.name
    "managed-by"       = "terraform-gcp-plane"
  })
}

# Other modules take project_id from network, so nothing is created before its API is enabled.
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

# Reserved before the add-ons and Plane, so the IPs (and dns_records) never change with the Services.
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

  # Waits for the node pool. A module-level depends_on would defer every data source and make plans noisy.
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

  # extraObjects need the add-ons' CRDs and webhooks; on destroy, Plane goes first.
  addons_ready = module.addons.ready
}

# A warning, not an error: without a certificate the email app self-signs, which is fine for receiving mail.
check "email_certificate" {
  assert {
    condition     = !local.automated || !local.email.enabled || !local.email.load_balancer || local.email.certificate_secret != null
    error_message = "No email certificate (email.certificate_secret): the email service uses a self-signed one. That's fine for receiving mail; store a certificate in Secret Manager and set email.certificate_secret for a trusted one."
  }
}
