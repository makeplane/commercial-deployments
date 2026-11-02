# The Traefik NLB's placement (path A): public subnets when internet-facing, private when internal.
# Runs the addons module on its own with mock providers.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:user/test" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
}
mock_provider "helm" {}
mock_provider "time" {}

variables {
  name                    = "plane-test"
  region                  = "us-east-1"
  cluster_name            = "plane-test"
  vpc_id                  = "vpc-0123456789abcdef0"
  vpc_cidr                = "10.60.0.0/16"
  public_subnet_ids       = ["subnet-public-a", "subnet-public-b"]
  private_subnet_ids      = ["subnet-private-a", "subnet-private-b"]
  install_traefik         = true
  allowed_cidrs           = ["0.0.0.0/0"]
  load_balancer_scheme    = "internet-facing"
  issue_certificate       = false
  certificate_secret_arns = []
  secret_arns             = { app_keys = "arn:aws:secretsmanager:us-east-1:123456789012:secret:app-keys" }
  kms_key_arn             = "arn:aws:kms:us-east-1:123456789012:key/mock"
  cluster_ready           = "plane-test"
  tags                    = {}
}

run "internet_facing_public_subnets" {
  command = plan
  module {
    source = "./modules/addons"
  }

  assert {
    condition     = strcontains(helm_release.traefik[0].values[0], "subnet-public-a,subnet-public-b")
    error_message = "An internet-facing Traefik NLB must use the public subnets."
  }
}

run "internal_private_subnets" {
  command = plan
  module {
    source = "./modules/addons"
  }
  variables {
    load_balancer_scheme = "internal"
  }

  assert {
    condition     = strcontains(helm_release.traefik[0].values[0], "subnet-private-a,subnet-private-b")
    error_message = "An internal Traefik NLB must use the private subnets."
  }
}
