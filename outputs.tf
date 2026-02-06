output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (EKS nodes)"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_id" {
  description = "ID of the EKS cluster"
  value       = module.eks.cluster_id
}

output "eks_cluster_endpoint" {
  description = "Endpoint for the EKS cluster API"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for cluster authentication"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "eks_cluster_security_group_id" {
  description = "Security group ID of the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "eks_node_security_group_id" {
  description = "Security group ID of the EKS node group"
  value       = module.eks.node_security_group_id
}

output "configure_kubectl" {
  description = "Command to configure kubectl for the cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}"
}

output "eks_addon_versions" {
  description = "Versions of installed EKS add-ons"
  value       = module.eks.addon_versions
}

output "mq_broker_endpoints" {
  description = "Amazon MQ broker endpoints"
  value       = module.mq.broker_endpoints
}

output "redis_endpoint" {
  description = "Redis primary endpoint"
  value       = module.cache.redis_endpoint
}

output "redis_port" {
  description = "Redis port"
  value       = module.cache.redis_port
}

output "opensearch_endpoint" {
  description = "OpenSearch domain endpoint"
  value       = module.opensearch.domain_endpoint
}

output "opensearch_kibana_endpoint" {
  description = "OpenSearch Dashboards endpoint"
  value       = module.opensearch.kibana_endpoint
}

output "s3_bucket_id" {
  description = "S3 bucket ID"
  value       = module.object_store.bucket_id
}

output "rds_cluster_endpoint" {
  description = "RDS cluster writer endpoint"
  value       = module.rds.cluster_endpoint
}

output "rds_reader_endpoint" {
  description = "RDS cluster reader endpoint"
  value       = module.rds.reader_endpoint
}

output "rds_db_name" {
  description = "Database name"
  value       = module.rds.db_name
}

output "plane_password_secret_arn" {
  description = "ARN of the plane-password secret in Secrets Manager (contains rabbit_mq_password, opensearch_password)"
  value       = aws_secretsmanager_secret.plane_password.arn
  sensitive   = true
}

output "rds_password_secret_arn" {
  description = "ARN of the RDS master user password secret in Secrets Manager"
  value       = module.rds.master_user_secret[0].secret_arn
  sensitive   = true
}