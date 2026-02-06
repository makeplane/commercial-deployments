terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

module "plane_infra" {
  source = "./.."

  cluster_name        = var.cluster_name
  region              = var.region
  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones
  single_nat_gateway  = var.single_nat_gateway
  cluster_version     = var.cluster_version
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_disk_size      = var.node_disk_size
  node_group_name     = var.node_group_name
  tags                = var.tags

  # MQ, Cache, OpenSearch, Object Store (optional overrides)
  mq_username               = var.mq_username
  mq_engine_version         = var.mq_engine_version
  mq_instance_type          = var.mq_instance_type
  mq_deployment_mode        = var.mq_deployment_mode
  cache_node_type           = var.cache_node_type
  cache_num_nodes           = var.cache_num_nodes
  opensearch_master_username = var.opensearch_master_username
  opensearch_instance_type   = var.opensearch_instance_type
  opensearch_instance_count  = var.opensearch_instance_count
  bucket_name_prefix        = var.bucket_name_prefix
  enable_s3_vpc_endpoint    = var.enable_s3_vpc_endpoint

  # RDS Multi-AZ DB Cluster (PostgreSQL)
  db_name              = var.db_name
  db_username          = var.db_username
  db_engine_version    = var.db_engine_version
  db_instance_class    = var.db_instance_class
  db_allocated_storage = var.db_allocated_storage
  db_storage_type      = var.db_storage_type
  db_iops              = var.db_iops
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.plane_infra.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.plane_infra.private_subnet_ids
}

output "eks_cluster_id" {
  description = "EKS cluster ID"
  value       = module.plane_infra.eks_cluster_id
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.plane_infra.eks_cluster_endpoint
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = module.plane_infra.configure_kubectl
}

output "mq_broker_endpoints" {
  description = "Amazon MQ broker endpoints"
  value       = module.plane_infra.mq_broker_endpoints
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.plane_infra.redis_endpoint
}

output "opensearch_endpoint" {
  description = "OpenSearch endpoint"
  value       = module.plane_infra.opensearch_endpoint
}

output "s3_bucket_id" {
  description = "S3 bucket ID"
  value       = module.plane_infra.s3_bucket_id
}

output "rds_cluster_endpoint" {
  description = "RDS cluster writer endpoint"
  value       = module.plane_infra.rds_cluster_endpoint
}

output "rds_reader_endpoint" {
  description = "RDS cluster reader endpoint"
  value       = module.plane_infra.rds_reader_endpoint
}

output "rds_db_name" {
  description = "Database name"
  value       = module.plane_infra.rds_db_name
}

output "plane_password_secret_arn" {
  description = "ARN of the plane-password secret (contains rabbit_mq_password, opensearch_password)"
  value       = module.plane_infra.plane_password_secret_arn
  sensitive   = true
}

output "rds_password_secret_arn" {
  description = "ARN of the RDS master user password secret in Secrets Manager"
  value       = module.plane_infra.rds_password_secret_arn
  sensitive   = true
}
