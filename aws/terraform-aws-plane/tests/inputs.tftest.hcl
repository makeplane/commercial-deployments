# Input rules: network ranges, admin principals, PostgreSQL storage and the cache replicas. Mock providers:
# no AWS credentials or cluster needed. Run: terraform init && terraform test

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
}

run "accepts_valid_inputs" {
  command = plan
  variables {
    vpc_cidr                             = "10.20.0.0/20"
    cluster_endpoint_public_access_cidrs = ["203.0.113.0/24", "198.51.100.10/32"]
    cluster_admin_principal_arns         = ["arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_Admin_0123456789abcdef", "arn:aws:iam::123456789012:user/ops"]
    ingress                              = { allowed_cidrs = ["192.0.2.0/24"] }
    redis                                = { replicas = 5 }
    postgres                             = { storage_type = "gp3", allocated_storage_gb = 400, iops = 12000 }
  }
}

run "accepts_gp3_without_iops" {
  command = plan
  variables {
    postgres = { storage_type = "gp3", allocated_storage_gb = 100 }
  }
}

run "reject_vpc_cidr_not_a_cidr" {
  command = plan
  variables { vpc_cidr = "10.60.0.0" }
  expect_failures = [var.vpc_cidr]
}

run "reject_vpc_cidr_not_range_start" {
  command = plan
  variables { vpc_cidr = "10.60.1.0/16" }
  expect_failures = [var.vpc_cidr]
}

run "reject_vpc_cidr_ipv6" {
  command = plan
  variables { vpc_cidr = "fd00::/48" }
  expect_failures = [var.vpc_cidr]
}

run "reject_vpc_cidr_too_large" {
  command = plan
  variables { vpc_cidr = "10.0.0.0/8" }
  expect_failures = [var.vpc_cidr]
}

run "reject_vpc_cidr_too_small" {
  command = plan
  variables { vpc_cidr = "10.60.0.0/24" }
  expect_failures = [var.vpc_cidr]
}

run "reject_endpoint_cidrs_empty" {
  command = plan
  variables { cluster_endpoint_public_access_cidrs = [] }
  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}

run "reject_endpoint_cidr_invalid" {
  command = plan
  variables { cluster_endpoint_public_access_cidrs = ["203.0.113.300/32"] }
  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}

run "reject_endpoint_cidr_host_bits" {
  command = plan
  variables { cluster_endpoint_public_access_cidrs = ["203.0.113.5/24"] }
  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}

run "reject_ingress_cidr_invalid" {
  command = plan
  variables { ingress = { allowed_cidrs = ["office"] } }
  expect_failures = [var.ingress]
}

run "reject_ingress_cidrs_empty" {
  command = plan
  variables { ingress = { allowed_cidrs = [] } }
  expect_failures = [var.ingress]
}

run "reject_admin_assumed_role_session" {
  command = plan
  variables { cluster_admin_principal_arns = ["arn:aws:sts::123456789012:assumed-role/Admin/alice"] }
  expect_failures = [var.cluster_admin_principal_arns]
}

run "reject_admin_not_an_arn" {
  command = plan
  variables { cluster_admin_principal_arns = ["Admin"] }
  expect_failures = [var.cluster_admin_principal_arns]
}

run "reject_admin_duplicate" {
  command = plan
  variables { cluster_admin_principal_arns = ["arn:aws:iam::123456789012:role/Admin", "arn:aws:iam::123456789012:role/Admin"] }
  expect_failures = [var.cluster_admin_principal_arns]
}

run "reject_redis_replicas_too_many" {
  command = plan
  variables { redis = { replicas = 6 } }
  expect_failures = [var.redis]
}

run "reject_redis_replicas_negative" {
  command = plan
  variables { redis = { replicas = -1 } }
  expect_failures = [var.redis]
}

run "reject_redis_replicas_fraction" {
  command = plan
  variables { redis = { replicas = 1.5 } }
  expect_failures = [var.redis]
}

run "reject_postgres_engine_version" {
  command = plan
  variables { postgres = { engine_version = "15" } }
  expect_failures = [var.postgres]
}

run "reject_postgres_storage_type" {
  command = plan
  variables { postgres = { storage_type = "gp2" } }
  expect_failures = [var.postgres]
}

run "reject_postgres_io1_small" {
  command = plan
  variables { postgres = { allocated_storage_gb = 50 } }
  expect_failures = [var.postgres]
}

run "reject_postgres_io1_iops_low" {
  command = plan
  variables { postgres = { iops = 500 } }
  expect_failures = [var.postgres]
}

run "reject_postgres_io1_iops_ratio" {
  command = plan
  variables { postgres = { allocated_storage_gb = 100, iops = 6000 } }
  expect_failures = [var.postgres]
}

run "reject_postgres_gp3_small_with_iops" {
  command = plan
  variables { postgres = { storage_type = "gp3", allocated_storage_gb = 100, iops = 3000 } }
  expect_failures = [var.postgres]
}

run "reject_postgres_gp3_iops_out_of_range" {
  command = plan
  variables { postgres = { storage_type = "gp3", allocated_storage_gb = 500, iops = 80000 } }
  expect_failures = [var.postgres]
}
