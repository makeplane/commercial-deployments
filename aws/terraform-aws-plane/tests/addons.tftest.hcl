# Path A's Traefik: the NLB's placement (public subnets when internet-facing, private when internal) and the
# client-IP headers it drops; path B installs no Traefik. Runs the addons module on its own with mock providers.

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
mock_provider "local" {}
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
  assert {
    condition = yamldecode(helm_release.traefik[0].values[0]).extraObjects == [{
      apiVersion = "traefik.io/v1alpha1"
      kind       = "Middleware"
      metadata   = { name = "strip-client-ip-headers", namespace = "traefik" }
      spec       = { headers = { customRequestHeaders = { "CF-Connecting-IP" = "", "True-Client-IP" = "" } } }
    }]
    error_message = "Traefik must ship the Middleware that drops the client-set CF-Connecting-IP and True-Client-IP headers."
  }
  assert {
    condition = (
      yamldecode(helm_release.traefik[0].values[0]).ports.web.http.middlewares == ["traefik-strip-client-ip-headers@kubernetescrd"]
      && yamldecode(helm_release.traefik[0].values[0]).ports.websecure.http.middlewares == ["traefik-strip-client-ip-headers@kubernetescrd"]
    )
    error_message = "Both entry points must apply the header Middleware to every request."
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

run "path_b_no_traefik" {
  command = plan
  module {
    source = "./modules/addons"
  }
  variables {
    install_traefik = false
  }

  assert {
    condition     = length(helm_release.traefik) == 0
    error_message = "Path B installs no Traefik, so no header Middleware: the customer's ingress drops the headers."
  }
}

# The mock check reports the AWS CLI found (exit code 0), so the releases are planned.
run "aws_cli_found" {
  command = plan
  module {
    source = "./modules/addons"
  }

  assert {
    condition     = data.local_command.aws_cli.command == "sh" && data.local_command.aws_cli.arguments == tolist(["-c", "command -v aws >/dev/null"])
    error_message = "Outside Windows the AWS CLI check must look aws up on PATH through sh."
  }
  assert {
    condition     = helm_release.external_secrets.name == "external-secrets"
    error_message = "With the AWS CLI found, the releases must be planned."
  }
}

run "aws_cli_missing" {
  command = plan
  module {
    source = "./modules/addons"
  }
  override_data {
    target = data.local_command.aws_cli
    values = { exit_code = 1 }
  }

  # The plan stops before any Helm release is read or planned.
  expect_failures = [data.local_command.aws_cli]
}
