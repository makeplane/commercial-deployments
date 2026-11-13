# The migration guide's infrastructure step (docs/migration-guide.md, 6.3): keep this target list the same
# as the guide's command. Everything Plane's first start and the data copy need must exist afterwards.

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
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/mock" }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:mock-AbCdEf" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::plane-v4-uploads-mock", id = "plane-v4-uploads-mock" }
  }
  mock_resource "aws_rds_cluster" {
    defaults = {
      endpoint           = "postgres.mock"
      port               = 5432
      database_name      = "plane"
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds-AbCdEf", kms_key_id = "mock", secret_status = "active" }]
    }
  }
  mock_resource "aws_mq_broker" {
    defaults = { instances = [{ console_url = "https://b.mq.us-east-1.amazonaws.com", endpoints = ["amqps://b.mq.us-east-1.amazonaws.com:5671"], ip_address = "" }] }
  }
  mock_resource "aws_elasticache_replication_group" {
    defaults = { primary_endpoint_address = "redis.mock", port = 6379 }
  }
}
mock_provider "helm" {}
mock_provider "random" {
  mock_resource "random_password" {
    defaults = { result = "abcdefghijklmnopqrstuvwxyz012345" }
  }
}
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
    cluster_name                       = "plane-v4"
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw=="
    ready                              = "plane-v4"
    node_security_group_id             = "sg-0123456789abcdef0"
  }
}

variables {
  name   = "plane-v4"
  domain = "plane.example.com"
}

run "infrastructure_without_plane" {
  plan_options {
    target = [module.network, module.cluster, module.data, module.addons, module.edge]
  }

  assert {
    condition = alltrue([
      module.data.bucket_name == "plane-v4-uploads-mock",
      module.data.rabbitmq_host != null,
      module.data.redis_host == "redis.mock",
      module.data.postgres_host == "postgres.mock",
    ])
    error_message = "The guide's targets must create the bucket, cache, queue and database."
  }
}
