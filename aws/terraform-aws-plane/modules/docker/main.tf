# Docker mode: Plane's Compose stack on one EC2 instance, set up by an SSM association that Terraform waits on.

data "aws_region" "current" {}
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  region    = data.aws_region.current.region
  partition = data.aws_partition.current.partition

  # Path A: Caddy terminates TLS. Path B: Caddy serves plain HTTP on :80 behind the customer's load balancer.
  automated = var.ingress.mode == "automated"
  public    = local.automated && var.ingress.scheme == "internet-facing"

  web_certificate_arn   = local.automated ? var.ingress.tls_certificate_secret_arn : null
  email_certificate_arn = var.email.enabled ? var.email.certificate_secret_arn : null
  certificate_arns      = compact([local.web_certificate_arn, local.email_certificate_arn])

  # SMTP from anywhere with a public IP, else from where Plane is reachable.
  smtp_cidrs = !(var.email.enabled && var.email.load_balancer) ? [] : (
    local.public ? ["0.0.0.0/0"] : (local.automated ? var.ingress.allowed_cidrs : [var.vpc_cidr])
  )

  assets_s3 = startswith(var.docker.compose_assets_url, "s3://") ? regex("^s3://([^/]+)/?(.*)$", var.docker.compose_assets_url) : null

  # No empty values: ${VAR:-default} in the compose file treats empty as unset. AES_SALT and DEPLOY_PLATFORM
  # stay unset: the compose file doesn't pass them, and a generated salt would break stored data once it does.
  plane_env = merge(
    var.docker.extra_env,
    {
      INSTALL_DIR          = "/opt/plane"
      DOMAIN_NAME          = var.domain
      APP_RELEASE_VERSION  = var.plane_version
      IS_AIRGAPPED         = "0"
      APP_PROTOCOL         = "https"
      WEB_URL              = "https://${var.domain}"
      CORS_ALLOWED_ORIGINS = "https://${var.domain}"
      SITE_ADDRESS         = local.automated ? var.domain : ":80"
      CERT_ACME_CA         = var.acme_server
      # Not yet passed to the proxy by the compose file.
      TRUSTED_PROXIES = local.automated ? "127.0.0.1/32" : var.vpc_cidr

      OPENSEARCH_ENABLED     = "0"
      POSTGRES_USER          = "plane"
      POSTGRES_DB            = "plane"
      RABBITMQ_USER          = "plane"
      RABBITMQ_DEFAULT_USER  = "plane"
      RABBITMQ_VHOST         = "plane"
      RABBITMQ_DEFAULT_VHOST = "plane"

      SILO_REPLICAS        = var.enable_components.silo ? "1" : "0"
      PI_API_REPLICAS      = var.enable_components.pi ? "1" : "0"
      PI_BEAT_REPLICAS     = var.enable_components.pi ? "1" : "0"
      PI_WORKER_REPLICAS   = var.enable_components.pi ? "1" : "0"
      PI_MIGRATOR_REPLICAS = var.enable_components.pi ? "1" : "0"

      EMAIL_REPLICAS = var.email.enabled ? "1" : "0"
      # variables.env ships 10025/10465/10587.
      LISTEN_SMTP_PORT_25  = "25"
      LISTEN_SMTP_PORT_465 = "465"
      LISTEN_SMTP_PORT_587 = "587"
    },
    var.acme_email == null ? {} : { CERT_EMAIL = var.acme_email },
    !var.email.enabled ? {} : {
      SMTP_DOMAIN         = var.email.smtp_domain
      INTAKE_EMAIL_DOMAIN = var.email.smtp_domain
    },
    local.email_certificate_arn == null ? {} : {
      TLS_CERT_PATH     = "tls/cert.pem"
      TLS_PRIV_KEY_PATH = "tls/key.pem"
    },
  )

  data_tags = merge(var.tags, {
    "plane.so/deployment" = var.name
    "plane.so/volume"     = "data"
  })
}
