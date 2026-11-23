# App keys: generated once, in the module's own secret, at the addresses existing installs have.
# Mock providers: no AWS credentials or cluster needed.

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
    defaults = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/plane-test/generated-AbCdEf" }
  }
  mock_resource "aws_rds_cluster" {
    defaults = { master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds-AbCdEf" }] }
  }
  mock_resource "aws_mq_broker" {
    defaults = { instances = [{ endpoints = ["amqps://b-mock.mq.us-east-1.on.aws:5671"] }] }
  }
}
mock_provider "helm" {}
mock_provider "local" {}
mock_provider "random" {
  # Long enough for the ElastiCache and Amazon MQ password rules.
  mock_resource "random_password" {
    defaults = { result = "mockmockmockmockmockmockmockmock" }
  }
}
mock_provider "time" {}
mock_provider "tls" {}
mock_provider "null" {}

# The data and plane modules run for real (with mocks); network and cluster are fixed outputs.
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

variables {
  name   = "plane-test"
  domain = "plane.example.com"
  # Every key the chart reads from external_secrets.app_keys_existingSecret.
  app_keys = [
    "SECRET_KEY", "AES_SECRET_KEY", "AES_SALT", "LIVE_SERVER_SECRET_KEY", "PI_INTERNAL_SECRET",
    "SILO_HMAC_SECRET_KEY", "CURSOR_WEBHOOK_SECRET", "RUNNER_HMAC_SECRET_KEY",
  ]
}

run "generated_by_default" {
  assert {
    condition     = output.secret_arns.app_keys == "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/plane-test/generated-AbCdEf"
    error_message = "By default the module must generate the app keys in its own secret."
  }
  assert {
    condition = [
      for o in yamldecode(output.plane_helm_values).extraObjects :
      sort([for d in o.spec.data : d.secretKey]) == sort(var.app_keys) && alltrue([for d in o.spec.data : d.remoteRef.key == output.secret_arns.app_keys])
      if o.metadata.name == "plane-app-keys"
    ] == [true]
    error_message = "plane-app-keys must map every app key from the generated secret."
  }
}

# The data module on its own: the keys' resource addresses must not change.
run "generated_addresses" {
  module {
    source = "./modules/data"
  }
  variables {
    vpc_id                    = "vpc-0123456789abcdef0"
    private_subnet_ids        = ["subnet-0a", "subnet-0b", "subnet-0c"]
    allowed_security_group_id = "sg-0123456789abcdef0"
    postgres                  = { engine_version = "15.19", instance_class = "db.m6gd.large", allocated_storage_gb = 100, storage_type = "io1", iops = 1000, backup_retention_days = 14, deletion_protection = true, apply_immediately = false }
    redis                     = { engine_version = "8.2", node_type = "cache.t3.medium", replicas = 0 }
    rabbitmq                  = { engine_version = "3.13", instance_type = "mq.m7g.medium", deployment_mode = "CLUSTER_MULTI_AZ" }
    opensearch                = { enabled = true, engine_version = "OpenSearch_2.19", instance_type = "r7g.large.search", instance_count = 2, volume_size_gb = 10, index_prefix = "plane" }
    bucket_force_destroy      = false
    tags                      = {}
  }

  assert {
    condition     = length(aws_secretsmanager_secret.app_keys) == 1 && length(aws_secretsmanager_secret_version.app_keys) == 1 && sort(keys(random_password.app_keys)) == sort(var.app_keys)
    error_message = "The app keys must stay at app_keys[0] and random_password.app_keys[<key name>]."
  }
  assert {
    condition     = output.plane_inputs.app_keys_secret_arn == aws_secretsmanager_secret.app_keys[0].arn
    error_message = "Plane must read the generated secret."
  }
}
