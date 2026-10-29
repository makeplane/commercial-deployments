# The two edge paths (A: ingress.mode = "automated", B: "none") and their input rules. Mock
# providers: no AWS credentials or cluster needed. Run: terraform init && terraform test

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
  mock_data "aws_iam_session_context" {
    defaults = { issuer_arn = "arn:aws:iam::123456789012:user/test" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
}
mock_provider "helm" {}
mock_provider "random" {}
mock_provider "time" {}
mock_provider "tls" {}
mock_provider "null" {}

# The edge logic lives in the root wiring and the addons, edge and plane modules: the network,
# cluster and data layers are replaced by fixed outputs.
override_module {
  target = module.network
  outputs = {
    vpc_id             = "vpc-0123456789abcdef0"
    private_subnet_ids = ["subnet-0a", "subnet-0b", "subnet-0c"]
    public_subnet_ids  = ["subnet-1a", "subnet-1b", "subnet-1c"]
  }
}

override_module {
  target = module.cluster
  outputs = {
    cluster_name                       = "plane-test"
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw=="
    ready                              = "plane-test"
    node_security_group_id             = "sg-0123456789abcdef0"
  }
}

override_module {
  target = module.data
  outputs = {
    kms_key_arn   = "arn:aws:kms:us-east-1:123456789012:key/mock"
    postgres_host = "postgres.mock"
    redis_host    = "redis.mock"
    rabbitmq_host = "rabbitmq.mock"
    bucket_name   = "plane-test-uploads"
    secret_arns = {
      postgres = "arn:aws:secretsmanager:us-east-1:123456789012:secret:postgres"
      redis    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:redis"
      rabbitmq = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rabbitmq"
      app_keys = "arn:aws:secretsmanager:us-east-1:123456789012:secret:app-keys"
    }
    plane_inputs = {
      kms_key_arn            = "arn:aws:kms:us-east-1:123456789012:key/mock"
      bucket_name            = "plane-test-uploads"
      bucket_arn             = "arn:aws:s3:::plane-test-uploads"
      postgres_host          = "postgres.mock"
      postgres_port          = 5432
      postgres_db            = "plane"
      postgres_secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:postgres"
      redis_host             = "redis.mock"
      redis_port             = 6379
      redis_secret_arn       = "arn:aws:secretsmanager:us-east-1:123456789012:secret:redis"
      rabbitmq_host          = "rabbitmq.mock"
      rabbitmq_port          = 5671
      rabbitmq_secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rabbitmq"
      app_keys_secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:app-keys"
      opensearch_enabled     = true
      opensearch_endpoint    = "opensearch.mock"
      opensearch_domain_name = "plane-test"
      opensearch_domain_arn  = "arn:aws:es:us-east-1:123456789012:domain/plane-test"
      opensearch_prefix      = "plane"
    }
  }
}

variables {
  name   = "plane-test"
  domain = "plane.example.com"
}

run "path_b_default" {
  assert {
    condition     = output.load_balancer_dns_name == null && output.dns_records.web == null
    error_message = "Path B must not have a Traefik load balancer or a web record."
  }
  assert {
    condition     = output.dns_records.email_mx != null
    error_message = "The email NLB (on by default) must give an MX record."
  }
  assert {
    condition     = !yamldecode(output.plane_helm_values).ingress.enabled
    error_message = "Path B must not install Plane's routes."
  }
  assert {
    condition     = !contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.kind], "ClusterIssuer")
    error_message = "Path B must not issue certificates."
  }
}

run "a1_lets_encrypt" {
  variables {
    ingress    = { mode = "automated" }
    acme_email = "ops@example.com"
  }

  # No email certificate: a warning, not an error.
  expect_failures = [check.email_certificate]

  assert {
    condition     = output.load_balancer_dns_name != null && output.dns_records.web.value == output.load_balancer_dns_name
    error_message = "Path A must expose the Traefik NLB and the web record."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).ingress.enabled
    error_message = "Path A must install Plane's routes."
  }
  assert {
    condition     = contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.kind], "ClusterIssuer")
    error_message = "A.1 must issue the web certificate with cert-manager."
  }
  assert {
    condition     = !contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.metadata.name], "plane-web-tls")
    error_message = "A.1 must not read a web certificate from Secrets Manager."
  }
}

run "a2_own_certificates" {
  variables {
    ingress = { mode = "automated", tls_certificate_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/web-tls" }
    email   = { certificate_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/mail-tls" }
  }

  assert {
    condition     = output.load_balancer_dns_name != null
    error_message = "Path A must expose the Traefik NLB."
  }
  assert {
    condition = alltrue([
      for n in ["plane-web-tls", "plane-mail-tls"] :
      contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.metadata.name], n)
    ])
    error_message = "A.2 must sync the web and email certificates from Secrets Manager."
  }
  assert {
    condition     = !contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.kind], "ClusterIssuer")
    error_message = "A.2 must not use Let's Encrypt."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).services.email_service.tls_secret_name == "plane-mail-tls-secret"
    error_message = "The email service must use the synced email certificate."
  }
}

run "path_b_email_certificate" {
  variables {
    email = { certificate_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/mail-tls" }
  }

  assert {
    condition     = contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.metadata.name], "plane-mail-tls")
    error_message = "The email certificate must be synced in path B too."
  }
}

run "reject_unknown_mode" {
  command = plan
  variables {
    ingress = { mode = "nginx" }
  }
  expect_failures = [var.ingress]
}

run "reject_automated_without_certificate" {
  command = plan
  variables {
    ingress = { mode = "automated" }
  }
  expect_failures = [var.ingress]
}

run "reject_automated_with_both_certificates" {
  command = plan
  variables {
    ingress    = { mode = "automated", tls_certificate_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/web-tls" }
    acme_email = "ops@example.com"
  }
  expect_failures = [var.ingress]
}

run "reject_lets_encrypt_restricted" {
  command = plan
  variables {
    ingress    = { mode = "automated", allowed_cidrs = ["203.0.113.0/24"] }
    acme_email = "ops@example.com"
  }
  expect_failures = [var.ingress]
}

run "reject_lets_encrypt_internal" {
  command = plan
  variables {
    ingress    = { mode = "automated", scheme = "internal" }
    acme_email = "ops@example.com"
  }
  expect_failures = [var.ingress]
}
