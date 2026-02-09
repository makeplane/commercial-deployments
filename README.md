# Plane Commercial Deployments

Deploy [Plane](https://plane.so) (open-source project management) on AWS. This repository provides:

1. **Terraform** — Provisions the AWS infrastructure (VPC, EKS, Redis, Amazon MQ RabbitMQ, OpenSearch, S3, RDS PostgreSQL)
2. **Kustomize** — Deploys the Plane application on the EKS cluster (coming soon)

## Prerequisites

- **Terraform** >= 1.0 — [Download](https://developer.hashicorp.com/terraform/downloads)
- **AWS CLI** configured with credentials — [Install](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **kubectl** for cluster access — [Install](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- **Kustomize** (for application deployment) — [Install](https://kustomize.io/) (or use `kubectl kustomize` built-in)

---

## Step 1: Deploy Infrastructure (Terraform)

From the repository root:

```bash
terraform init
terraform plan
terraform apply
```

### Minimal Configuration

The root [main.tf](main.tf) deploys `plane_infra` with minimal required inputs. Defaults are used for EKS, cache, OpenSearch, object store, and database.

```hcl
module "plane_infra" {
  source = "git::https://github.com/makeplane/commercial-deployments.git//terraform?ref=main"
  # source = "./terraform"  # for local development

  cluster_name       = "plane-eks-cluster"
  region             = "us-west-2" # required
  vpc_cidr           = "10.0.0.0/16"
  single_nat_gateway = true
  cluster_version    = "1.34"

  tags = {
    Environment = "plane"
  }
}
```

Override defaults by passing `eks`, `cache`, `mq`, `opensearch`, `object_store`, or `db` objects. See [terraform/README.md](terraform/README.md) for all options.

### Outputs

Add these output blocks to your configuration to expose module outputs (e.g. in `main.tf` or `outputs.tf`):

```hcl
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

output "mq_broker_id" {
  description = "Amazon MQ RabbitMQ broker ID"
  value       = module.plane_infra.mq_broker_id
}

output "mq_broker_endpoints" {
  description = "Amazon MQ RabbitMQ broker endpoints (AMQP)"
  value       = module.plane_infra.mq_broker_endpoints
}

output "mq_security_group_id" {
  description = "Security group ID of the Amazon MQ broker"
  value       = module.plane_infra.mq_security_group_id
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
  description = "ARN of the plane-password secret (contains opensearch_password, mq_password)"
  value       = module.plane_infra.plane_password_secret_arn
  sensitive   = true
}

output "rds_password_secret_arn" {
  description = "ARN of the RDS master user password secret in Secrets Manager"
  value       = module.plane_infra.rds_password_secret_arn
  sensitive   = true
}
```

| Output | Description |
|--------|-------------|
| `vpc_id` | VPC ID |
| `private_subnet_ids` | Private subnet IDs |
| `eks_cluster_id` | EKS cluster ID |
| `eks_cluster_endpoint` | EKS API endpoint |
| `configure_kubectl` | Command to configure kubectl |
| `redis_endpoint` | Redis endpoint |
| `mq_broker_id` | Amazon MQ RabbitMQ broker ID |
| `mq_broker_endpoints` | Amazon MQ RabbitMQ broker endpoints (AMQP) |
| `mq_security_group_id` | Amazon MQ broker security group ID |
| `opensearch_endpoint` | OpenSearch endpoint |
| `s3_bucket_id` | S3 bucket ID |
| `rds_cluster_endpoint` | RDS writer endpoint |
| `rds_reader_endpoint` | RDS reader endpoint |
| `rds_db_name` | Database name |
| `plane_password_secret_arn` | OpenSearch and MQ passwords (Secrets Manager) |
| `rds_password_secret_arn` | RDS password (Secrets Manager) |

### Configure kubectl

```bash
aws eks update-kubeconfig --region us-west-2 --name plane-eks-cluster
```

---

## Step 2: Deploy Plane (Kustomize)

*Kustomize manifests and deployment steps will be added here.*

After infrastructure is ready:

1. Retrieve secrets from AWS Secrets Manager (OpenSearch, MQ, and RDS passwords)
2. Apply Kustomize manifests to deploy Plane on the EKS cluster
3. Configure ingress and access

---

## Cleanup

To destroy infrastructure:

```bash
terraform destroy
```

**Warning**: This deletes all data in RDS, OpenSearch, Redis, Amazon MQ, and S3. Ensure backups exist if needed.
