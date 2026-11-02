# Secrets Manager entries, in the JSON shape the plane-enterprise chart reads through External
# Secrets. The RDS master secret is created and rotated by RDS itself (postgres.tf).

resource "aws_secretsmanager_secret" "valkey" {
  # checkov:skip=CKV2_AWS_57:The ElastiCache AUTH token isn't rotated automatically in this release.
  name                    = "plane/${var.name}/redis"
  description             = "Plane (${var.name}) ElastiCache AUTH token"
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 7

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "valkey" {
  secret_id     = aws_secretsmanager_secret.valkey.id
  secret_string = jsonencode({ password = random_password.valkey_auth.result })
}

resource "aws_secretsmanager_secret" "rabbitmq" {
  # checkov:skip=CKV2_AWS_57:The Amazon MQ user password isn't rotated automatically in this release.
  name                    = "plane/${var.name}/rabbitmq"
  description             = "Plane (${var.name}) Amazon MQ user"
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 7

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "rabbitmq" {
  secret_id     = aws_secretsmanager_secret.rabbitmq.id
  secret_string = jsonencode({ username = "plane", password = random_password.rabbitmq.result })
}

# Signing and encryption keys shared by api, live, silo and pi (chart external_secrets.app_keys_existingSecret).
# SECRET_KEY, AES_SECRET_KEY and AES_SALT encrypt stored data: they are generated once and must
# never change, or existing ciphertext becomes unreadable without any error.
locals {
  app_key_lengths = {
    SECRET_KEY             = 50
    AES_SECRET_KEY         = 32
    AES_SALT               = 32
    LIVE_SERVER_SECRET_KEY = 48
    PI_INTERNAL_SECRET     = 48
    SILO_HMAC_SECRET_KEY   = 48
    CURSOR_WEBHOOK_SECRET  = 48
    RUNNER_HMAC_SECRET_KEY = 48
  }
  # An existing installation brings its own keys (app_keys_secret_arn): nothing is generated.
  generate_app_keys   = var.app_keys_secret_arn == null
  app_keys_secret_arn = local.generate_app_keys ? aws_secretsmanager_secret.app_keys[0].arn : var.app_keys_secret_arn
}

resource "random_password" "app_keys" {
  for_each = local.generate_app_keys ? local.app_key_lengths : {}

  length  = each.value
  special = false
}

resource "aws_secretsmanager_secret" "app_keys" {
  # checkov:skip=CKV2_AWS_57:These keys encrypt stored data and must never rotate.
  count = local.generate_app_keys ? 1 : 0

  name                    = "plane/${var.name}/app-keys"
  description             = "Plane (${var.name}) signing and encryption keys. Never rotate."
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 7

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "app_keys" {
  count = local.generate_app_keys ? 1 : 0

  secret_id     = aws_secretsmanager_secret.app_keys[0].id
  secret_string = jsonencode({ for k, v in random_password.app_keys : k => v.result })
}

# Addresses before app_keys_secret_arn: keep the secret, never recreate it.
moved {
  from = aws_secretsmanager_secret.app_keys
  to   = aws_secretsmanager_secret.app_keys[0]
}

moved {
  from = aws_secretsmanager_secret_version.app_keys
  to   = aws_secretsmanager_secret_version.app_keys[0]
}
