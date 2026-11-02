output "plane_url" {
  description = "URL Plane is served on."
  value       = "https://${var.domain}"
}

output "deployment_mode" {
  description = "Deployment mode in use."
  value       = var.deployment_mode
}

output "load_balancer_dns_name" {
  description = "Path A: hostname of the Traefik NLB (null in path B). Point domain here with a CNAME (or an alias record in Route 53), never A records to its current IPs: AWS assigns them and they can change."
  value       = module.edge.load_balancer_dns_name
}

output "email_load_balancer_dns_name" {
  description = "Hostname of the email NLB (null without email.load_balancer). email.smtp_domain's MX record points here."
  value       = module.plane.email_load_balancer_dns_name
}

output "dns_records" {
  description = "The DNS records to create (the module creates none). web: path A only; in path B, point domain at your own ingress load balancer."
  value = {
    web = module.edge.load_balancer_dns_name == null ? null : {
      name  = var.domain
      type  = "CNAME (or alias A in Route 53; DNS-only, no proxy)"
      value = module.edge.load_balancer_dns_name
    }
    email_mx = module.plane.email_load_balancer_dns_name == null ? null : {
      name  = local.email.smtp_domain
      type  = "MX"
      value = "10 ${module.plane.email_load_balancer_dns_name}"
    }
  }
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

output "plane_helm_values" {
  description = "The plane-enterprise chart values the module generates from the infrastructure (YAML): endpoints, bucket, region, domain, load balancer and Secret names; no secret values. Excludes plane_values. For support, debugging and reading what was installed."
  value       = module.plane.helm_values
}
