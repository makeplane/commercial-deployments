# Plane Commercial Deployments

Deploy [Plane](https://plane.so) (open-source project management) on AWS. This repository provides:

1. **Terraform** — Provisions the AWS infrastructure (VPC, EKS, Redis, OpenSearch, S3, RDS PostgreSQL)
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
  source = "git::https://github.com/your-org/commercial-deployments.git?ref=main"
  #source = "./terraform" for local deployment

  cluster_name       = "plane-eks-cluster"
  region             = "us-west-2"
  vpc_cidr           = "10.0.0.0/16"
  single_nat_gateway = true
  cluster_version    = "1.34"

  tags = {
    Environment = "plane"
  }
}
```

Override defaults by passing `eks`, `cache`, `opensearch`, `object_store`, or `db` objects. See [terraform/README.md](terraform/README.md) for all options.

### Outputs

After apply, Terraform outputs include:

| Output | Description |
|--------|-------------|
| `vpc_id` | VPC ID |
| `private_subnet_ids` | Private subnet IDs |
| `eks_cluster_id` | EKS cluster ID |
| `eks_cluster_endpoint` | EKS API endpoint |
| `configure_kubectl` | Command to configure kubectl |
| `redis_endpoint` | Redis endpoint |
| `opensearch_endpoint` | OpenSearch endpoint |
| `s3_bucket_id` | S3 bucket ID |
| `rds_cluster_endpoint` | RDS writer endpoint |
| `rds_reader_endpoint` | RDS reader endpoint |
| `rds_db_name` | Database name |
| `plane_password_secret_arn` | OpenSearch password (Secrets Manager) |
| `rds_password_secret_arn` | RDS password (Secrets Manager) |

### Configure kubectl

```bash
aws eks update-kubeconfig --region us-west-2 --name plane-eks-cluster
```

---

## Step 2: Deploy Plane (Kustomize)

*Kustomize manifests and deployment steps will be added here.*

After infrastructure is ready:

1. Retrieve secrets from AWS Secrets Manager (OpenSearch and RDS passwords)
2. Apply Kustomize manifests to deploy Plane on the EKS cluster
3. Configure ingress and access

---

## Cleanup

To destroy infrastructure:

```bash
terraform destroy
```

**Warning**: This deletes all data in RDS, OpenSearch, Redis, and S3. Ensure backups exist if needed.
