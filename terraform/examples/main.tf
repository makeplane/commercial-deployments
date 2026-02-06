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

  cluster_name       = var.cluster_name
  region             = var.region
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  single_nat_gateway = var.single_nat_gateway
  cluster_version    = var.cluster_version
  tags               = var.tags

  eks          = var.eks
  cache        = var.cache
  opensearch   = var.opensearch
  object_store = var.object_store
  db           = var.db
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
  description = "ARN of the plane-password secret (contains opensearch_password)"
  value       = module.plane_infra.plane_password_secret_arn
  sensitive   = true
}

output "rds_password_secret_arn" {
  description = "ARN of the RDS master user password secret in Secrets Manager"
  value       = module.plane_infra.rds_password_secret_arn
  sensitive   = true
}
