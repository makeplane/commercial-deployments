# RDS PostgreSQL storage settings, major version upgrades and the master password. Runs the data module on its own
# with mock providers.

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
  mock_resource "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/plane-test/mock-AbCdEf" }
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
    apply_immediately     = false
  }
  redis                = { engine_version = "8.2", node_type = "cache.t3.medium", replicas = 1 }
  rabbitmq             = { engine_version = "3.13", instance_type = "mq.m7g.medium", deployment_mode = "CLUSTER_MULTI_AZ" }
  opensearch           = { enabled = false, engine_version = "OpenSearch_2.19", instance_type = "r7g.large.search", instance_count = 2, volume_size_gb = 10, index_prefix = "plane" }
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
      apply_immediately     = false
    }
  }

  assert {
    condition     = aws_rds_cluster.postgres.storage_type == "gp3" && aws_rds_cluster.postgres.iops == null
    error_message = "gp3 under 400 GiB must not send IOPS (a fixed 3000 baseline)."
  }
}

# A major upgrade: install on 15, then change engine_version to 16 in the same state.
run "install_15" {
  module {
    source = "./modules/data"
  }

  assert {
    condition     = aws_rds_cluster.postgres.db_cluster_parameter_group_name == "plane-test-pg15" && aws_rds_cluster_parameter_group.postgres.family == "postgres15"
    error_message = "PostgreSQL 15 must use the postgres15 cluster parameter group."
  }
  assert {
    condition     = aws_rds_cluster.postgres.allow_major_version_upgrade && !aws_rds_cluster.postgres.apply_immediately
    error_message = "The cluster must allow major upgrades and leave changes to the maintenance window by default."
  }
}

run "major_upgrade_16" {
  command = plan
  module {
    source = "./modules/data"
  }
  variables {
    postgres = {
      engine_version        = "16.6"
      instance_class        = "db.m6gd.large"
      allocated_storage_gb  = 100
      storage_type          = "io1"
      iops                  = null
      backup_retention_days = 14
      deletion_protection   = true
      apply_immediately     = true
    }
  }

  assert {
    condition     = aws_rds_cluster_parameter_group.postgres.name == "plane-test-pg16" && aws_rds_cluster_parameter_group.postgres.family == "postgres16"
    error_message = "A major upgrade must plan a new parameter group of the new family, under a new name (created before the old one is deleted)."
  }
  assert {
    condition     = aws_rds_cluster.postgres.engine_version == "16.6" && aws_rds_cluster.postgres.allow_major_version_upgrade && aws_rds_cluster.postgres.apply_immediately
    error_message = "A major upgrade must plan the new engine version, allowed and applied immediately."
  }
}

# Not RDS-managed (its rotation broke Plane's connections): the module's password, in the module's own secret.
# Version 1 sets no keepers, so an install from before password_version keeps its password on upgrade.
run "postgres_password_version_default" {
  module {
    source = "./modules/data"
  }
  override_resource {
    target = aws_secretsmanager_secret.postgres
    values = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/plane-test/postgres-AbCdEf" }
  }

  assert {
    condition     = random_password.postgres.keepers == null && random_password.postgres.length == 40 && !random_password.postgres.special
    error_message = "At the default password_version the password must have no keepers (40 characters, no specials)."
  }
  assert {
    condition     = aws_rds_cluster.postgres.manage_master_user_password != true && aws_rds_cluster.postgres.master_password == random_password.postgres.result
    error_message = "RDS must not manage the master password; the cluster must use the generated one."
  }
  assert {
    condition = (
      aws_secretsmanager_secret.postgres.name == "plane/plane-test/postgres" &&
      aws_secretsmanager_secret.postgres.kms_key_id == aws_kms_key.this.arn &&
      jsondecode(aws_secretsmanager_secret_version.postgres.secret_string) == { username = "plane", password = random_password.postgres.result }
    )
    error_message = "The secret must be KMS-encrypted with the module's key and hold the username and password plane-db reads."
  }
  assert {
    condition = (
      output.plane_inputs.postgres_secret_arn == aws_secretsmanager_secret.postgres.arn &&
      output.secret_arns.postgres == aws_secretsmanager_secret.postgres.arn
    )
    error_message = "plane-db and External Secrets' policy must use the module's postgres secret."
  }
  assert {
    condition = (
      sort(keys(output.secret_arns)) == tolist(["app_keys", "postgres", "rabbitmq", "redis"]) &&
      !anytrue([for a in values(output.secret_arns) : strcontains(a, ":secret:rds!")])
    )
    error_message = "External Secrets must be scoped to exactly the module's four secrets, none RDS-managed."
  }
}

run "postgres_password_version_bump" {
  module {
    source = "./modules/data"
  }
  variables {
    postgres = {
      engine_version        = "15.19"
      instance_class        = "db.m6gd.large"
      allocated_storage_gb  = 100
      storage_type          = "io1"
      iops                  = null
      backup_retention_days = 14
      deletion_protection   = true
      apply_immediately     = false
      password_version      = 2
    }
  }

  assert {
    condition     = random_password.postgres.keepers == tomap({ version = "2" })
    error_message = "postgres.password_version must reach the password's keepers."
  }
  assert {
    condition = (
      aws_rds_cluster.postgres.master_password == random_password.postgres.result &&
      jsondecode(aws_secretsmanager_secret_version.postgres.secret_string).password == random_password.postgres.result
    )
    error_message = "The cluster and the secret External Secrets reads must carry the rotated password."
  }
}
