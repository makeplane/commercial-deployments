# Docker mode through the root module, with mock providers (no AWS credentials needed).

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:user/test" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0", insecure_value = "ami-0123456789abcdef0" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/mock" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/mock" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::plane-test-backups-mock", id = "plane-test-backups-mock" }
  }
  mock_resource "aws_instance" {
    defaults = { id = "i-0123456789abcdef0", private_ip = "10.60.0.10" }
  }
  mock_resource "aws_eip" {
    defaults = { public_ip = "203.0.113.10" }
  }
  mock_resource "aws_ssm_document" {
    defaults = { default_version = "1", latest_version = "1" }
  }
  mock_resource "aws_ssm_association" {
    defaults = { association_id = "11111111-2222-3333-4444-555555555555" }
  }
}
mock_provider "helm" {}
mock_provider "random" {}
mock_provider "time" {}

override_module {
  target = module.network
  outputs = {
    vpc_id             = "vpc-0123456789abcdef0"
    private_subnet_ids = ["subnet-0a", "subnet-0b", "subnet-0c"]
    public_subnet_ids  = ["subnet-1a", "subnet-1b", "subnet-1c"]
  }
}

variables {
  name            = "plane-test"
  domain          = "plane.example.com"
  deployment_mode = "docker"
}

# Input rules below run in path B, so the email-certificate warning (path A) stays out of the way.

# The Quickstart: path A by default, Let's Encrypt, email on.
run "a1_quickstart" {
  variables {
    acme_email = "ops@example.com"
  }

  # No email certificate: a warning, not an error.
  expect_failures = [check.email_certificate]

  assert {
    condition = alltrue([for v in [
      output.cluster_name, output.cluster_endpoint, output.configure_kubectl, output.load_balancer_dns_name,
      output.email_load_balancer_dns_name, output.rds_endpoint, output.s3_bucket_name, output.plane_helm_values,
    ] : v == null])
    error_message = "Docker mode must create none of the EKS layers."
  }
  assert {
    condition     = output.instance_public_ip == "203.0.113.10" && output.dns_records.web.value == output.instance_public_ip && startswith(output.dns_records.web.type, "A")
    error_message = "Path A internet-facing: an A record to the Elastic IP."
  }
  assert {
    condition     = output.dns_records.email_mx.name == "intake.plane.example.com" && output.dns_records.email_mx.value == "10 plane.example.com"
    error_message = "Email on: MX for intake.<domain> pointing at domain."
  }
  assert {
    condition     = output.plane_env.SITE_ADDRESS == "plane.example.com" && output.plane_env.CERT_EMAIL == "ops@example.com" && output.plane_env.EMAIL_REPLICAS == "1"
    error_message = "A.1: Caddy serves the domain with Let's Encrypt; email runs."
  }
  assert {
    condition     = output.plane_env.APP_RELEASE_VERSION == "v4.0.1" && output.plane_env.WEB_URL == "https://plane.example.com"
    error_message = "plane.env must carry the version and the URL."
  }
  assert {
    condition     = strcontains(output.ssm_session_command, "i-0123456789abcdef0") && strcontains(output.rerun_setup_command, "11111111-2222-3333-4444-555555555555")
    error_message = "Docker mode must give the session and re-run commands."
  }
  assert {
    condition     = keys(output.secret_arns) == ["app_keys", "bundled_services"]
    error_message = "secret_arns must list the Docker secrets."
  }
}

run "a2_internal" {
  variables {
    ingress = {
      scheme                     = "internal"
      allowed_cidrs              = ["10.0.0.0/8"]
      tls_certificate_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/web-tls"
    }
    email = { certificate_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/mail-tls" }
  }

  assert {
    condition     = output.instance_public_ip == null && output.dns_records.web.value == "10.60.0.10"
    error_message = "Internal: no Elastic IP; the A record points at the private IP."
  }
  assert {
    condition     = output.dns_records.email_mx == null
    error_message = "Internal: no MX record (the instance isn't reachable from the internet)."
  }
  assert {
    condition     = !contains(keys(output.plane_env), "CERT_EMAIL") && output.plane_env.TLS_CERT_PATH == "tls/cert.pem"
    error_message = "A.2: no Let's Encrypt; the email certificate is used."
  }
}

run "path_b" {
  variables {
    ingress = { mode = "none" }
  }

  assert {
    condition     = output.dns_records.web == null && output.dns_records.email_mx == null && output.instance_public_ip == null
    error_message = "Path B: no Elastic IP and no records; domain points at your load balancer."
  }
  assert {
    condition     = output.plane_env.SITE_ADDRESS == ":80" && output.plane_env.TRUSTED_PROXIES == "10.60.0.0/16"
    error_message = "Path B: plain HTTP on :80 behind a proxy in the VPC."
  }
}

run "components_and_email_off" {
  variables {
    acme_email        = "ops@example.com"
    email             = { enabled = false }
    enable_components = { silo = false, pi = true }
    docker            = { extra_env = { GUNICORN_WORKERS = "4" } }
  }

  assert {
    condition     = output.dns_records.email_mx == null && output.plane_env.EMAIL_REPLICAS == "0" && !contains(keys(output.plane_env), "SMTP_DOMAIN")
    error_message = "email.enabled = false: no email service, no MX record."
  }
  assert {
    condition     = output.plane_env.SILO_REPLICAS == "0" && output.plane_env.PI_API_REPLICAS == "1" && output.plane_env.PI_MIGRATOR_REPLICAS == "1"
    error_message = "enable_components must map to replica counts."
  }
  assert {
    condition     = output.plane_env.GUNICORN_WORKERS == "4"
    error_message = "extra_env must reach plane.env."
  }
}

run "docker_needs_a_certificate_source" {
  command         = plan
  expect_failures = [var.ingress]
}

run "reject_burstable_instance" {
  command = plan
  variables {
    ingress = { mode = "none" }
    docker  = { instance_type = "t3.xlarge" }
  }
  expect_failures = [var.docker]
}

run "reject_hybrid_data" {
  command = plan
  variables {
    ingress = { mode = "none" }
    docker  = { data_services = "hybrid" }
  }
  expect_failures = [var.docker]
}

run "reject_managed_key_in_extra_env" {
  command = plan
  variables {
    ingress = { mode = "none" }
    docker  = { extra_env = { SECRET_KEY = "x" } }
  }
  expect_failures = [var.docker]
}

run "reject_bad_assets" {
  command = plan
  variables {
    ingress = { mode = "none" }
    docker = {
      compose_assets_url    = "http://example.com/assets"
      compose_assets_sha256 = { "compose.yaml" = "abc" }
    }
  }
  expect_failures = [var.docker]
}

run "reject_bad_snapshot" {
  command = plan
  variables {
    ingress = { mode = "none" }
    docker  = { data_volume_snapshot_id = "vol-0123" }
  }
  expect_failures = [var.docker]
}

run "reject_plane_values_in_docker" {
  command = plan
  variables {
    ingress      = { mode = "none" }
    plane_values = "services: {}"
  }
  expect_failures = [var.plane_values]
}

run "reject_unknown_deployment_mode" {
  command = plan
  variables {
    deployment_mode = "ecs"
  }
  expect_failures = [var.deployment_mode]
}
