output "plane_url" {
  description = "URL Plane is served on."
  value       = "https://${var.domain}"
}

output "deployment_mode" {
  description = "Deployment mode in use."
  value       = var.deployment_mode
}

output "load_balancer_dns_name" {
  description = "EKS path A: hostname of the Traefik NLB (null in path B and in Docker mode). Point domain here with a CNAME (or an alias record in Route 53), never A records to its current IPs: AWS assigns them and they can change."
  value       = one(module.edge[*].load_balancer_dns_name)
}

output "email_load_balancer_dns_name" {
  description = "EKS: hostname of the email NLB (null without email.load_balancer, and in Docker mode). email.smtp_domain's MX record points here."
  value       = one(module.plane[*].email_load_balancer_dns_name)
}

output "dns_records" {
  description = "The DNS records to create (the module creates none). web: EKS path A (CNAME to the NLB) or Docker path A (A record to the Elastic IP, or to the private IP when internal); null in path B, where domain points at your own load balancer. email_mx: the MX record for email.smtp_domain."
  value = local.docker ? {
    web = !local.automated ? null : {
      name  = var.domain
      type  = "A (DNS-only, no proxy)"
      value = local.docker_public ? module.docker[0].public_ip : module.docker[0].private_ip
    }
    email_mx = !(local.docker_public && local.email.enabled && local.email.load_balancer) ? null : {
      name  = local.email.smtp_domain
      type  = "MX"
      value = "10 ${var.domain}"
    }
    } : {
    web = one(module.edge[*].load_balancer_dns_name) == null ? null : {
      name  = var.domain
      type  = "CNAME (or alias A in Route 53; DNS-only, no proxy)"
      value = one(module.edge[*].load_balancer_dns_name)
    }
    email_mx = one(module.plane[*].email_load_balancer_dns_name) == null ? null : {
      name  = local.email.smtp_domain
      type  = "MX"
      value = "10 ${one(module.plane[*].email_load_balancer_dns_name)}"
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
  description = "EKS cluster name (null in Docker mode)."
  value       = one(module.cluster[*].cluster_name)
}

output "cluster_endpoint" {
  description = "EKS API endpoint (null in Docker mode)."
  value       = one(module.cluster[*].cluster_endpoint)
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster CA (base64; null in Docker mode)."
  value       = one(module.cluster[*].cluster_certificate_authority_data)
}

output "configure_kubectl" {
  description = "Command to point kubectl at the cluster (null in Docker mode)."
  value       = local.eks ? "aws eks update-kubeconfig --region ${local.region} --name ${one(module.cluster[*].cluster_name)}" : null
}

output "rds_endpoint" {
  description = "RDS cluster writer endpoint (EKS mode)."
  value       = one(module.data[*].postgres_host)
}

output "redis_endpoint" {
  description = "ElastiCache primary endpoint (TLS; EKS mode)."
  value       = one(module.data[*].redis_host)
}

output "rabbitmq_endpoint" {
  description = "Amazon MQ AMQPS host (EKS mode)."
  value       = one(module.data[*].rabbitmq_host)
}

output "s3_bucket_name" {
  description = "Uploads bucket (EKS mode; Docker mode stores uploads in the bundled MinIO)."
  value       = one(module.data[*].bucket_name)
}

output "secret_arns" {
  description = "Secrets Manager ARNs the deployment uses (ARNs only, never values)."
  value       = try(module.data[0].secret_arns, module.docker[0].secret_arns)
}

output "kms_key_arn" {
  description = "KMS key encrypting the data: RDS, ElastiCache, S3 and the secrets (EKS); the volumes, secrets and backups (Docker)."
  value       = try(module.data[0].kms_key_arn, module.docker[0].kms_key_arn)
}

output "plane_iam_role_arn" {
  description = "IAM role Plane's pods use through EKS Pod Identity (null in Docker mode)."
  value       = one(module.plane[*].iam_role_arn)
}

output "plane_helm_values" {
  description = "The plane-enterprise chart values the module generates from the infrastructure (YAML): endpoints, bucket, region, domain, load balancer and Secret names; no secret values. Excludes plane_values. For support, debugging and reading what was installed. Null in Docker mode (see plane_env)."
  value       = one(module.plane[*].helm_values)
}

################################################################################
# Docker mode (null in EKS mode)
################################################################################

output "plane_env" {
  description = "Docker mode: the plane.env settings the module manages, without the secrets (those come from Secrets Manager on the instance). The rest of plane.env is Plane's variables.env for plane_version."
  value       = one(module.docker[*].plane_env)
}

output "instance_id" {
  description = "Docker mode: EC2 instance ID."
  value       = one(module.docker[*].instance_id)
}

output "instance_public_ip" {
  description = "Docker mode: the Elastic IP (path A internet-facing; null otherwise). It survives instance replacement."
  value       = one(module.docker[*].public_ip)
}

output "instance_private_ip" {
  description = "Docker mode: private IP of the instance (path B: your load balancer's target, port 80)."
  value       = one(module.docker[*].private_ip)
}

output "instance_security_group_id" {
  description = "Docker mode: security group of the instance."
  value       = one(module.docker[*].security_group_id)
}

output "data_volume_id" {
  description = "Docker mode: EBS data volume mounted at /opt/plane."
  value       = one(module.docker[*].data_volume_id)
}

output "backup_bucket_name" {
  description = "Docker mode: S3 bucket with the nightly database dumps, the MinIO mirror and the SSM command output."
  value       = one(module.docker[*].backup_bucket_name)
}

output "ssm_session_command" {
  description = "Docker mode: shell on the instance through SSM Session Manager (no SSH). Needs the Session Manager plugin for the AWS CLI."
  value       = local.docker ? "aws ssm start-session --region ${local.region} --target ${module.docker[0].instance_id}" : null
}

output "rerun_setup_command" {
  description = "Docker mode: run the converge (setup, upgrade, repair) again without a Terraform change."
  value       = local.docker ? "aws ssm start-associations-once --region ${local.region} --association-ids ${module.docker[0].converge_association_id}" : null
}

output "ssm_output_s3_uri" {
  description = "Docker mode: where the setup, backup and certificate jobs write their output (one folder per run)."
  value       = one(module.docker[*].ssm_output_s3_uri)
}
