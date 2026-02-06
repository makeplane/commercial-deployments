# Plane Commercial Deployments Terraform Module

A Terraform module that provisions AWS infrastructure for running [Plane](https://plane.so) (open-source project management). It deploys: VPC, EKS (with cert-manager and EBS CSI add-ons), ElastiCache (Redis), OpenSearch, S3, and RDS PostgreSQL.

## Prerequisites

- **Terraform** >= 1.0
- **AWS CLI** configured with appropriate credentials
- **kubectl** for cluster access after deployment

Your AWS credentials must have permissions to create and manage: VPC, EKS, RDS, ElastiCache, OpenSearch, S3, Secrets Manager, and IAM resources.

## Architecture

The module deploys a multi-AZ infrastructure across 3 availability zones:

- **Private subnets**: EKS nodes, RDS, and ElastiCache (Redis) run in private subnets
- **Public subnets**: NAT gateways and load balancers
- **OpenSearch**: Deployed with a public endpoint, secured with HTTPS and fine-grained access control (username/password authentication)
- **VPC endpoints**: Optional S3 gateway endpoint for private access to object storage
- **Secrets Manager**: RDS and OpenSearch passwords are auto-generated and stored securely
- **EKS add-ons**: cert-manager and EBS CSI driver are installed automatically

## Quick Start

The [examples/](examples/) directory contains a complete configuration. From the repository root:

```bash
cd examples

# Copy the sample config and customize
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform plan
terraform apply
```

Or use a separate var file to keep your values out of the working tree:

```bash
cd examples

cp terraform.tfvars.example terraform.tfvars.local
# Edit terraform.tfvars.local with your values

terraform init
terraform plan -var-file=terraform.tfvars.local
terraform apply -var-file=terraform.tfvars.local
```

## Configuration

See [examples/terraform.tfvars.example](examples/terraform.tfvars.example) and [examples/variables.tf](examples/variables.tf) for all options, including:

- **VPC**: Custom CIDR, availability zones, single vs multi-AZ NAT gateways
- **EKS**: Node group scaling, instance types, disk size. cert-manager and EBS CSI add-ons are installed automatically
- **Cache (Redis)**: ElastiCache node type, cluster count (1 for single node, 2+ for replica)
- **OpenSearch**: Publicly accessible with HTTPS and authentication. Configure instance type, instance count, master username — password is auto-generated and stored in Secrets Manager
- **RDS (PostgreSQL)**: Multi-AZ DB Cluster with 1 writer and 2 readers. Database name, engine version, instance class, storage — master password is managed in Secrets Manager
- **Object Store**: S3 bucket prefix, optional VPC gateway endpoint for private access
- **Tags**: Custom tags for all resources

## Infrastructure Details

- **Cost optimization**: Set `single_nat_gateway = true` to use one NAT gateway (lower cost) or `false` for one per AZ (higher availability)
- **Security**: Passwords are auto-generated and stored in AWS Secrets Manager. Security groups restrict access between components
- **High availability**: RDS and OpenSearch use multi-AZ deployments. Use `single_nat_gateway = false` for NAT redundancy

## Outputs

After apply, the following outputs are available:

| Category | Outputs |
|----------|---------|
| VPC | `vpc_id`, `private_subnet_ids`, `public_subnet_ids` |
| EKS | `eks_cluster_endpoint`, `configure_kubectl`, `eks_addon_versions` |
| Services | `redis_endpoint`, `opensearch_endpoint`, `opensearch_kibana_endpoint`, `s3_bucket_id`, `rds_cluster_endpoint`, `rds_reader_endpoint`, `rds_db_name` |
| Secrets | `plane_password_secret_arn` (OpenSearch), `rds_password_secret_arn` |

## Post-Deployment

**Configure kubectl**:
```bash
aws eks update-kubeconfig --region <region> --name <cluster_name>
```

**Retrieve passwords from Secrets Manager**:
```bash
# OpenSearch password (stored in plane-password secret)
aws secretsmanager get-secret-value --secret-id <cluster_name>/plane-password --query SecretString --output text | jq -r .opensearch_password

# RDS password
aws secretsmanager get-secret-value --secret-id <rds_password_secret_arn> --query SecretString --output text
```

**Connect to services**:
- **RDS and Redis**: Accessible only from within the VPC (e.g., from EKS pods) as they run in private subnets
- **OpenSearch**: Publicly accessible via HTTPS using the master username and password from Secrets Manager

**Deploy Plane**: This module provisions infrastructure only. To deploy the Plane application on the EKS cluster, see [Plane's deployment documentation](https://docs.plane.so/self-hosting).

## Cleanup

To destroy all resources:

```bash
cd examples
terraform destroy
```

**Warning**: This permanently deletes all data in RDS, OpenSearch, Redis, and S3. Ensure you have backups if needed. If using a separate var file:

```bash
terraform destroy -var-file=terraform.tfvars.local
```

If destroy fails (e.g., due to dependencies or finalizers), you may need to manually remove resources in the AWS console or retry after resolving the reported issues.

## Module Usage

Use this repository as a Terraform module in your own project:

```hcl
module "plane_infra" {
  source = "git::https://github.com/your-org/commercial-deployments.git?ref=main"
  # Or use a local path: source = "../commercial-deployments"

  cluster_name        = "plane-eks-cluster"
  region              = "us-west-2"
  vpc_cidr            = "10.0.0.0/16"
  single_nat_gateway  = true
  cluster_version     = "1.34"
  node_instance_types = ["t3.large"]
  node_desired_size   = 2
  node_min_size       = 2
  node_max_size       = 4

  cache_node_type     = "cache.t3.micro"
  cache_num_nodes     = 1
  bucket_name_prefix  = "plane"
  db_name             = "planedb"

  tags = {
    Environment = "plane"
  }
}

output "eks_endpoint" {
  value = module.plane_infra.eks_cluster_endpoint
}
```

See [examples/main.tf](examples/main.tf) for all available input variables and [outputs.tf](outputs.tf) for outputs.
