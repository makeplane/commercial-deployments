# One SSM Command document carries the scripts and the non-secret configuration (base64, written to
# /usr/local/lib/plane and /etc/plane) and runs plane-converge.sh in one of three modes:
#   converge  install or upgrade Plane to the configured state; Terraform waits for it (association below)
#   backup    nightly pg_dump and MinIO mirror to the backups bucket
#   certs     daily copy of the certificates from Secrets Manager (only with your own certificates)
# Secret values are never in the document: the script reads them with the instance role.

locals {
  plane_conf = {
    PLANE_DOMAIN            = var.domain
    PLANE_VERSION           = var.plane_version
    ASSETS_URL              = var.docker.compose_assets_url
    ASSETS_SHA256_COMPOSE   = lookup(var.docker.compose_assets_sha256, "docker-compose.yml", "")
    ASSETS_SHA256_VARIABLES = lookup(var.docker.compose_assets_sha256, "variables.env", "")
    DOCKER_VERSION          = var.docker.docker_version
    COMPOSE_VERSION         = var.docker.compose_version
    DATA_VOLUME_ID          = aws_ebs_volume.data.id
    AWS_REGION              = local.region
    APP_KEYS_SECRET         = aws_secretsmanager_secret.app_keys.arn
    BUNDLED_SECRET          = aws_secretsmanager_secret.bundled.arn
    WEB_CERT_SECRET         = local.web_certificate_arn == null ? "" : local.web_certificate_arn
    EMAIL_CERT_SECRET       = local.email_certificate_arn == null ? "" : local.email_certificate_arn
    BACKUP_BUCKET           = aws_s3_bucket.backups.id
    SETUP_TIMEOUT_SECONDS   = var.docker.setup_timeout_minutes * 60
  }

  # Shell assignments, single-quoted (sourced by the script).
  plane_conf_text = join("", [
    for k in sort(keys(local.plane_conf)) : "${k}='${replace(tostring(local.plane_conf[k]), "'", "'\\''")}'\n"
  ])
  # KEY=value lines, merged into plane.env by the script.
  plane_env_text = join("", [for k in sort(keys(local.plane_env)) : "${k}=${local.plane_env[k]}\n"])

  instance_files = {
    "/usr/local/lib/plane/lib-common.sh"     = file("${path.module}/scripts/lib-common.sh")
    "/usr/local/lib/plane/lib-aws.sh"        = file("${path.module}/scripts/lib-aws.sh")
    "/usr/local/lib/plane/plane-converge.sh" = file("${path.module}/scripts/plane-converge.sh")
    "/etc/plane/plane.conf"                  = local.plane_conf_text
    "/etc/plane/managed.env"                 = local.plane_env_text
  }

  # POSIX sh: SSM may run the commands with /bin/sh.
  run_command = concat(
    ["set -eu", "umask 077", "install -d -m 0700 /usr/local/lib/plane /etc/plane"],
    flatten([for path, content in local.instance_files : [
      "printf '%s' '${base64encode(content)}' | base64 -d > '${path}.new'",
      "chmod 0700 '${path}.new' && mv -f '${path}.new' '${path}'",
    ]]),
    ["exec /usr/local/lib/plane/plane-converge.sh '{{ Mode }}'"],
  )

  backup_hour_minute = split(":", var.docker.backup_time)
  ssm_output_prefix  = "ssm"
}

resource "aws_ssm_document" "this" {
  name            = "${var.name}-plane"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Plane (${var.name}): converge the Docker Compose stack, back it up or sync certificates."
    parameters = {
      Mode = {
        type          = "String"
        description   = "converge, backup or certs"
        default       = "converge"
        allowedValues = ["converge", "backup", "certs"]
      }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "plane"
      inputs = {
        timeoutSeconds = tostring(var.docker.setup_timeout_minutes * 60)
        runCommand     = local.run_command
      }
    }]
  })

  tags = var.tags
}

# Install, upgrade or reconfigure. Re-created whenever the document or the instance changes, so every change
# runs once and Terraform waits for it (the provider waits on create only).
resource "aws_ssm_association" "converge" {
  name                             = aws_ssm_document.this.name
  association_name                 = "${var.name}-plane-converge"
  document_version                 = aws_ssm_document.this.default_version
  parameters                       = { Mode = "converge" }
  wait_for_success_timeout_seconds = var.docker.setup_timeout_minutes * 60

  targets {
    key    = "InstanceIds"
    values = [aws_instance.this.id]
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.backups.id
    s3_key_prefix  = "${local.ssm_output_prefix}/converge"
    s3_region      = local.region
  }

  lifecycle {
    replace_triggered_by = [aws_ssm_document.this, aws_instance.this.id]
  }

  depends_on = [
    aws_volume_attachment.data,
    aws_eip_association.this,
    aws_iam_role_policy.instance,
    aws_iam_role_policy_attachment.ssm,
    aws_secretsmanager_secret_version.app_keys,
    aws_secretsmanager_secret_version.bundled,
    aws_s3_bucket_server_side_encryption_configuration.backups,
    aws_s3_bucket_policy.backups,
  ]
}

resource "aws_ssm_association" "backup" {
  name                        = aws_ssm_document.this.name
  association_name            = "${var.name}-plane-backup"
  document_version            = aws_ssm_document.this.default_version
  parameters                  = { Mode = "backup" }
  schedule_expression         = "cron(${tonumber(local.backup_hour_minute[1])} ${tonumber(local.backup_hour_minute[0])} * * ? *)"
  apply_only_at_cron_interval = true

  targets {
    key    = "InstanceIds"
    values = [aws_instance.this.id]
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.backups.id
    s3_key_prefix  = "${local.ssm_output_prefix}/backup"
    s3_region      = local.region
  }

  depends_on = [aws_ssm_association.converge]
}

resource "aws_ssm_association" "certs" {
  count = length(local.certificate_arns) > 0 ? 1 : 0

  name                        = aws_ssm_document.this.name
  association_name            = "${var.name}-plane-certs"
  document_version            = aws_ssm_document.this.default_version
  parameters                  = { Mode = "certs" }
  schedule_expression         = "cron(30 4 * * ? *)"
  apply_only_at_cron_interval = true

  targets {
    key    = "InstanceIds"
    values = [aws_instance.this.id]
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.backups.id
    s3_key_prefix  = "${local.ssm_output_prefix}/certs"
    s3_region      = local.region
  }

  depends_on = [aws_ssm_association.converge]
}
