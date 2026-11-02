provider "aws" {
  region = var.region
}

# Plane on one EC2 instance with Docker Compose (bundled Postgres, Valkey, RabbitMQ and MinIO), served by the
# stack's Caddy proxy on an Elastic IP with a Let's Encrypt certificate. Terraform never connects to the
# instance: setup runs through SSM and the apply waits for it.
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
