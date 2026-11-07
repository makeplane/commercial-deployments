# RDS PostgreSQL storage settings. Runs the data module on its own with mock providers.

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
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/mock" }
  }
  mock_resource "aws_rds_cluster" {
    defaults = { master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds-AbCdEf" }] }
  }
  mock_resource "aws_mq_broker" {
    defaults = { instances = [{ endpoints = ["amqps://b-mock.mq.us-east-1.on.aws:5671"] }] }
  }
}
mock_provider "random" {
  mock_resource "random_password" {
    defaults = { result = "mockmockmockmockmockmockmockmock" }
  }
}

variables {
  name                      = "plane-test"
  domain                    = "plane.example.com"
  vpc_id                    = "vpc-0123456789abcdef0"
  private_subnet_ids        = ["subnet-0a", "subnet-0b", "subnet-0c"]
  allowed_security_group_id = "sg-0123456789abcdef0"
  postgres = {
    engine_version        = "15.19"
    instance_class        = "db.m6gd.large"
    allocated_storage_gb  = 100
    storage_type          = "io1"
    iops                  = null
    backup_retention_days = 14
    deletion_protection   = true
  }
  redis                = { engine_version = "8.2", node_type = "cache.t3.medium", replicas = 1 }
  rabbitmq             = { engine_version = "3.13", instance_type = "mq.m7g.medium", deployment_mode = "CLUSTER_MULTI_AZ" }
  opensearch           = { enabled = false, engine_version = "OpenSearch_2.19", instance_type = "r7g.large.search", instance_count = 2, volume_size_gb = 10, index_prefix = "plane" }
  app_keys_secret_arn  = null
  bucket_force_destroy = false
  tags                 = {}
}

run "io1_default_iops" {
  command = plan
  module {
    source = "./modules/data"
  }

  assert {
    condition     = aws_rds_cluster.postgres.storage_type == "io1" && aws_rds_cluster.postgres.iops == 1000
    error_message = "io1 without iops must get 1000 IOPS, as today's module."
  }
}

run "gp3_small_no_iops" {
  command = plan
  module {
    source = "./modules/data"
  }
  variables {
    postgres = {
      engine_version        = "15.19"
      instance_class        = "db.m6gd.large"
      allocated_storage_gb  = 100
      storage_type          = "gp3"
      iops                  = null
      backup_retention_days = 14
      deletion_protection   = true
    }
  }

  assert {
    condition     = aws_rds_cluster.postgres.storage_type == "gp3" && aws_rds_cluster.postgres.iops == null
    error_message = "gp3 under 400 GiB must not send IOPS (a fixed 3000 baseline)."
  }
}
