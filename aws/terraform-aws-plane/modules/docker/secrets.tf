# Each secret's JSON maps plane.env keys to values; the converge script writes them as they are.

# SECRET_KEY and AES_SECRET_KEY encrypt stored data: never rotate them.
resource "random_password" "app_keys" {
  for_each = {
    SECRET_KEY               = 50
    AES_SECRET_KEY           = 32
    SILO_HMAC_SECRET_KEY     = 48
    LIVE_SERVER_SECRET_KEY   = 48
    PI_INTERNAL_SECRET       = 48
    CURSOR_WEBHOOK_SECRET    = 48
    WEBHOOK_SECRET           = 48
    ARGUS_FINGERPRINT_SECRET = 64
    ARGUS_INTERNAL_SECRET    = 48
  }

  length  = each.value
  special = false
}

# Only used by Plane v4 to adopt a 3.x licence identity; kept stable so a replaced instance looks the same.
resource "random_id" "machine_signature" {
  byte_length = 16
}

resource "aws_secretsmanager_secret" "app_keys" {
  # checkov:skip=CKV2_AWS_57:These keys encrypt stored data and must never rotate.
  name                    = "plane/${var.name}/app-keys"
  description             = "Plane (${var.name}) signing and encryption keys. Never rotate."
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 7

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "app_keys" {
  secret_id = aws_secretsmanager_secret.app_keys.id
  secret_string = jsonencode(merge(
    { for k, v in random_password.app_keys : k => v.result },
    { MACHINE_SIGNATURE = random_id.machine_signature.hex },
  ))
}

# Every URL carrying a password is set too, so no default credential (plane:plane) survives anywhere.
resource "random_password" "bundled" {
  for_each = {
    postgres       = 32
    rabbitmq       = 32
    minio_user     = 20
    minio_password = 40
  }

  length  = each.value
  special = false
}

locals {
  postgres_password = random_password.bundled["postgres"].result
  rabbitmq_password = random_password.bundled["rabbitmq"].result
}

resource "aws_secretsmanager_secret" "bundled" {
  # checkov:skip=CKV2_AWS_57:The bundled services read these only at first initialisation; rotation isn't automated.
  name                    = "plane/${var.name}/bundled-services"
  description             = "Plane (${var.name}) bundled Postgres, RabbitMQ and MinIO credentials"
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 7

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "bundled" {
  secret_id = aws_secretsmanager_secret.bundled.id
  secret_string = jsonencode({
    POSTGRES_PASSWORD     = local.postgres_password
    DATABASE_URL          = "postgresql://plane:${local.postgres_password}@plane-db/plane"
    FOLLOWER_POSTGRES_URI = "postgresql://plane:${local.postgres_password}@plane-db/plane"
    PLANE_PI_DATABASE_URL = "postgresql://plane:${local.postgres_password}@plane-db/plane_pi"
    RABBITMQ_PASSWORD     = local.rabbitmq_password
    RABBITMQ_DEFAULT_PASS = local.rabbitmq_password
    AMQP_URL              = "amqp://plane:${local.rabbitmq_password}@plane-mq:5672/plane"
    MINIO_ROOT_USER       = random_password.bundled["minio_user"].result
    MINIO_ROOT_PASSWORD   = random_password.bundled["minio_password"].result
    AWS_ACCESS_KEY_ID     = random_password.bundled["minio_user"].result
    AWS_SECRET_ACCESS_KEY = random_password.bundled["minio_password"].result
  })
}
