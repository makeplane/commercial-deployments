# Customer Secrets Manager ARNs (web and email certificates, Plane AI keys; app_keys_secret_arn in
# app_keys.tftest.hcl): full ARN with its 6-character suffix, in this account and region. External Secrets is
# granted each exact ARN in this region's Secrets Manager, so anything else would fail at sync time.
# Mock providers: no AWS credentials or cluster needed. Run: terraform init && terraform test

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
    redis_port    = 6379
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
      app_key_names          = ["SECRET_KEY", "AES_SECRET_KEY"]
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

  web_tls    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/web-tls-AbCdEf"
  mail_tls   = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/mail-tls-AbCdEf"
  openai_key = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/openai-key-AbCdEf"
  cohere_key = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/cohere-key-AbCdEf"
}

run "accept_full_arns" {
  variables {
    ingress           = { mode = "automated", tls_certificate_secret_arn = var.web_tls }
    email             = { certificate_secret_arn = var.mail_tls }
    enable_components = { pi = true }
    pi                = { api_keys = { chat_key_secret_arn = var.openai_key, embedding_key_secret_arn = var.cohere_key } }
  }

  assert {
    condition = length(setsubtract([var.web_tls, var.mail_tls, var.openai_key, var.cohere_key], flatten([
      for o in yamldecode(output.plane_helm_values).extraObjects :
      concat([for d in try(o.spec.dataFrom, []) : d.extract.key], [for d in try(o.spec.data, []) : d.remoteRef.key])
    ]))) == 0
    error_message = "Every customer secret must be synced by its exact ARN."
  }
}

run "reject_web_certificate_partial_arn" {
  command = plan
  variables {
    ingress = { mode = "automated", tls_certificate_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/key" }
  }
  expect_failures = [var.ingress]
}

run "reject_web_certificate_other_account" {
  command = plan
  variables {
    ingress = { mode = "automated", tls_certificate_secret_arn = "arn:aws:secretsmanager:us-east-1:210987654321:secret:plane/key-AbCdEf" }
  }
  expect_failures = [var.ingress]
}

run "reject_web_certificate_other_region" {
  command = plan
  variables {
    ingress = { mode = "automated", tls_certificate_secret_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:plane/key-AbCdEf" }
  }
  expect_failures = [var.ingress]
}

run "reject_web_certificate_secret_name" {
  command = plan
  variables {
    ingress = { mode = "automated", tls_certificate_secret_arn = "plane/key" }
  }
  expect_failures = [var.ingress]
}

run "reject_email_certificate_partial_arn" {
  command = plan
  variables {
    email = { certificate_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/key" }
  }
  expect_failures = [var.email]
}

run "reject_email_certificate_other_account" {
  command = plan
  variables {
    email = { certificate_secret_arn = "arn:aws:secretsmanager:us-east-1:210987654321:secret:plane/key-AbCdEf" }
  }
  expect_failures = [var.email]
}

run "reject_email_certificate_other_region" {
  command = plan
  variables {
    email = { certificate_secret_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:plane/key-AbCdEf" }
  }
  expect_failures = [var.email]
}

run "reject_email_certificate_secret_name" {
  command = plan
  variables {
    email = { certificate_secret_arn = "plane/key" }
  }
  expect_failures = [var.email]
}

run "reject_chat_key_partial_arn" {
  command = plan
  variables {
    pi                = { api_keys = { chat_key_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/key", embedding_key_secret_arn = var.cohere_key } }
    enable_components = { pi = true }
  }
  expect_failures = [var.pi]
}

run "reject_chat_key_other_account" {
  command = plan
  variables {
    pi                = { api_keys = { chat_key_secret_arn = "arn:aws:secretsmanager:us-east-1:210987654321:secret:plane/key-AbCdEf", embedding_key_secret_arn = var.cohere_key } }
    enable_components = { pi = true }
  }
  expect_failures = [var.pi]
}

run "reject_chat_key_other_region" {
  command = plan
  variables {
    pi                = { api_keys = { chat_key_secret_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:plane/key-AbCdEf", embedding_key_secret_arn = var.cohere_key } }
    enable_components = { pi = true }
  }
  expect_failures = [var.pi]
}

run "reject_chat_key_secret_name" {
  command = plan
  variables {
    pi                = { api_keys = { chat_key_secret_arn = "plane/key", embedding_key_secret_arn = var.cohere_key } }
    enable_components = { pi = true }
  }
  expect_failures = [var.pi]
}

run "reject_embedding_key_partial_arn" {
  command = plan
  variables {
    pi                = { api_keys = { chat_key_secret_arn = var.openai_key, embedding_key_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/key" } }
    enable_components = { pi = true }
  }
  expect_failures = [var.pi]
}

run "reject_embedding_key_other_account" {
  command = plan
  variables {
    pi                = { api_keys = { chat_key_secret_arn = var.openai_key, embedding_key_secret_arn = "arn:aws:secretsmanager:us-east-1:210987654321:secret:plane/key-AbCdEf" } }
    enable_components = { pi = true }
  }
  expect_failures = [var.pi]
}

run "reject_embedding_key_other_region" {
  command = plan
  variables {
    pi                = { api_keys = { chat_key_secret_arn = var.openai_key, embedding_key_secret_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:plane/key-AbCdEf" } }
    enable_components = { pi = true }
  }
  expect_failures = [var.pi]
}

run "reject_embedding_key_secret_name" {
  command = plan
  variables {
    pi                = { api_keys = { chat_key_secret_arn = var.openai_key, embedding_key_secret_arn = "plane/key" } }
    enable_components = { pi = true }
  }
  expect_failures = [var.pi]
}
