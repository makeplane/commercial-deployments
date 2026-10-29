output "plane_url" {
  description = "URL Plane is served on."
  value       = "https://${var.domain}"
}

output "deployment_mode" {
  description = "Deployment mode in use."
  value       = var.deployment_mode
}

output "public_ips" {
  description = "Static public IPs of the load balancer. Point domain here when route53_zone_id is null."
  value       = module.edge.public_ips
}

output "dns_record_managed" {
  description = "Whether the module manages the DNS record (true when route53_zone_id is set)."
  value       = var.route53_zone_id != null
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.network.private_subnet_ids
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.cluster.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.cluster.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster CA (base64)."
  value       = module.cluster.cluster_certificate_authority_data
}

output "configure_kubectl" {
  description = "Command to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${local.region} --name ${module.cluster.cluster_name}"
}

output "rds_endpoint" {
  description = "RDS cluster writer endpoint."
  value       = module.data.postgres_host
}

output "redis_endpoint" {
  description = "ElastiCache primary endpoint (TLS)."
  value       = module.data.redis_host
}

output "rabbitmq_endpoint" {
  description = "Amazon MQ AMQPS host."
  value       = module.data.rabbitmq_host
}

output "s3_bucket_name" {
  description = "Uploads bucket."
  value       = module.data.bucket_name
}

output "secret_arns" {
  description = "Secrets Manager ARNs the deployment uses (ARNs only, never values)."
  value       = module.data.secret_arns
}

output "kms_key_arn" {
  description = "KMS key encrypting RDS, ElastiCache, S3 and the secrets."
  value       = module.data.kms_key_arn
}

output "plane_iam_role_arn" {
  description = "IAM role Plane's pods use through EKS Pod Identity."
  value       = module.plane.iam_role_arn
}
