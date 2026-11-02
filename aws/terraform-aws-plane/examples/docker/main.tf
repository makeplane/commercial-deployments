provider "aws" {
  region = var.region
}

module "plane" {
  # Registry source once published: source = "makeplane/plane/aws", version = "~> 0.2"
  source = "../../"

  name            = var.name
  domain          = var.domain
  deployment_mode = "docker"
  acme_email      = var.acme_email

  docker = {
    compose_assets_url    = var.compose_assets_url
    compose_assets_sha256 = var.compose_assets_sha256
  }
}
