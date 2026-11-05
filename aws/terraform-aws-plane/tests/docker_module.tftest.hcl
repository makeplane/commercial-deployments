# modules/docker on its own, with mock providers.

mock_provider "aws" {
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
  mock_resource "aws_ssm_document" {
    defaults = { default_version = "1", latest_version = "1" }
  }
}
mock_provider "random" {}

variables {
  name              = "plane-test"
  domain            = "plane.example.com"
  plane_version     = "v4.0.1"
  vpc_id            = "vpc-0123456789abcdef0"
  vpc_cidr          = "10.60.0.0/16"
  subnet_id         = "subnet-1a"
  availability_zone = "us-east-1a"
  ingress = {
    mode          = "automated"
    allowed_cidrs = ["0.0.0.0/0"]
    scheme        = "internet-facing"
  }
  acme_email  = "ops@example.com"
  acme_server = "https://acme-v02.api.letsencrypt.org/directory"
  email = {
    enabled       = true
    smtp_domain   = "intake.plane.example.com"
    load_balancer = true
  }
  enable_components = { silo = true, drawio = true, pi = false }
  docker = {
    instance_type         = "m7a.xlarge"
    data_services         = "bundled"
    root_volume_gb        = 50
    data_volume_gb        = 100
    compose_assets_url    = "https://prime.plane.so/deployment/assets"
    compose_assets_sha256 = {}
    docker_version        = "29.9.2"
    compose_version       = "5.6.1"
    extra_env             = {}
    backup_time           = "03:00"
    backup_retention_days = 14
    setup_timeout_minutes = 60
  }
  bucket_force_destroy = false
  tags                 = { "plane.so/deployment" = "plane-test" }
}

run "hardened_instance" {
  module {
    source = "./modules/docker"
  }

  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required" && aws_instance.this.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "IMDSv2 only, hop limit 1 (containers can't reach the instance role)."
  }
  assert {
    condition     = aws_instance.this.user_data == null && !aws_instance.this.associate_public_ip_address
    error_message = "No user data (nothing passed at launch) and no automatic public IP."
  }
  assert {
    condition = alltrue([
      aws_instance.this.root_block_device[0].encrypted, aws_ebs_volume.data.encrypted,
      aws_instance.this.root_block_device[0].kms_key_id == aws_kms_key.this.arn, aws_ebs_volume.data.kms_key_id == aws_kms_key.this.arn,
    ])
    error_message = "Root and data volumes must be encrypted with the module key."
  }
  assert {
    condition     = aws_ebs_volume.data.final_snapshot && aws_ebs_volume.data.tags["plane.so/volume"] == "data" && aws_volume_attachment.data.stop_instance_before_detaching
    error_message = "The data volume keeps a final snapshot, is tagged for DLM and is detached only after a clean stop."
  }
  assert {
    condition     = aws_dlm_lifecycle_policy.data.policy_details[0].target_tags["plane.so/volume"] == "data"
    error_message = "DLM must target the data volume."
  }
}

run "security_group_path_a" {
  module {
    source = "./modules/docker"
  }

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.this : r.from_port != 22])
    error_message = "Never port 22."
  }
  assert {
    condition     = toset([for r in aws_vpc_security_group_ingress_rule.this : r.from_port]) == toset([80, 443, 25, 465, 587])
    error_message = "Path A internet-facing with email: 80, 443 and the SMTP ports."
  }
  assert {
    condition     = length(aws_eip.this) == 1 && length(aws_eip_association.this) == 1
    error_message = "Path A internet-facing: an Elastic IP."
  }
}

run "path_b_from_vpc_only" {
  module {
    source = "./modules/docker"
  }
  variables {
    ingress    = { mode = "none", allowed_cidrs = ["0.0.0.0/0"], scheme = "internet-facing" }
    acme_email = null
    email      = { enabled = false, smtp_domain = "intake.plane.example.com", load_balancer = true }
  }

  assert {
    condition     = [for r in aws_vpc_security_group_ingress_rule.this : "${r.from_port}/${r.cidr_ipv4}"] == ["80/10.60.0.0/16"]
    error_message = "Path B: only port 80, only from the VPC."
  }
  assert {
    condition     = length(aws_eip.this) == 0
    error_message = "Path B: no Elastic IP."
  }
}

run "ssm_converge" {
  module {
    source = "./modules/docker"
  }

  assert {
    condition     = aws_ssm_association.converge.wait_for_success_timeout_seconds == 3600 && aws_ssm_association.converge.parameters.Mode == "converge"
    error_message = "Terraform must wait for the converge."
  }
  assert {
    condition     = aws_ssm_association.backup.schedule_expression == "cron(0 3 * * ? *)" && aws_ssm_association.backup.apply_only_at_cron_interval
    error_message = "Backups run nightly at backup_time, not at create."
  }
  assert {
    condition     = length(aws_ssm_association.certs) == 0
    error_message = "No certificate sync without certificate secrets."
  }
  assert {
    condition = alltrue(concat(
      [for k, v in random_password.app_keys : !strcontains(aws_ssm_document.this.content, v.result)],
      [for k, v in random_password.bundled : !strcontains(aws_ssm_document.this.content, v.result)],
      [!strcontains(aws_ssm_document.this.content, random_id.machine_signature.hex)],
    ))
    error_message = "No generated secret may appear in the SSM document."
  }
  assert {
    condition     = strcontains(aws_ssm_document.this.content, base64encode(file("./modules/docker/scripts/plane-converge.sh")))
    error_message = "The document must carry the converge script."
  }
}

run "own_certificates_and_s3_assets" {
  module {
    source = "./modules/docker"
  }
  variables {
    ingress = {
      mode                       = "automated"
      allowed_cidrs              = ["203.0.113.0/24", "2001:db8::/32"]
      scheme                     = "internet-facing"
      tls_certificate_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/web-tls"
    }
    acme_email = null
    email = {
      enabled                = true
      smtp_domain            = "intake.plane.example.com"
      load_balancer          = true
      certificate_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/mail-tls"
    }
    docker = {
      instance_type           = "m7a.xlarge"
      data_services           = "bundled"
      root_volume_gb          = 50
      data_volume_gb          = 100
      data_volume_snapshot_id = "snap-0123456789abcdef0"
      compose_assets_url      = "s3://acme-plane-assets/releases/"
      compose_assets_sha256   = {}
      docker_version          = "29.9.2"
      compose_version         = "5.6.1"
      extra_env               = {}
      backup_time             = "03:00"
      backup_retention_days   = 14
      setup_timeout_minutes   = 60
    }
  }

  assert {
    condition     = length(aws_ssm_association.certs) == 1
    error_message = "Own certificates: a daily certificate sync."
  }
  assert {
    condition = alltrue([for arn in ["arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/web-tls", "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/mail-tls"] :
    contains(flatten([for s in data.aws_iam_policy_document.instance.statement : s.resources if s.sid == "ReadPlaneSecrets"]), arn)])
    error_message = "The instance role must read both certificate secrets."
  }
  assert {
    condition     = contains(flatten([for s in data.aws_iam_policy_document.instance.statement : s.resources if s.sid == "ReadComposeAssets"]), "arn:aws:s3:::acme-plane-assets/releases/*")
    error_message = "s3:// assets: the role may read that prefix only."
  }
  assert {
    condition     = aws_ebs_volume.data.snapshot_id == "snap-0123456789abcdef0"
    error_message = "data_volume_snapshot_id must restore the data volume."
  }
  assert {
    condition     = contains([for r in aws_vpc_security_group_ingress_rule.this : r.cidr_ipv6], "2001:db8::/32") && contains([for r in aws_vpc_security_group_ingress_rule.this : r.from_port], 25)
    error_message = "IPv6 CIDRs and SMTP from anywhere (public instance)."
  }
}
