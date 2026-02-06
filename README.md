# Commercial Deployments Terraform Module

A Terraform module that provisions a complete AWS infrastructure: VPC, EKS (with cert-manager and EBS CSI add-ons), Amazon MQ (RabbitMQ), ElastiCache (Redis), OpenSearch, S3, and RDS PostgreSQL.

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
- **EKS**: Node group scaling, instance types, disk size, SSH key for node access
- **MQ (RabbitMQ)**: Username, instance type, deployment mode — password is auto-generated and stored in Secrets Manager
- **Cache (Redis)**: Node type, cluster count
- **OpenSearch**: Instance type, instance count
- **RDS (PostgreSQL)**: Database name, engine version, instance class, storage — master password is managed in Secrets Manager
- **Object Store**: S3 bucket prefix, VPC endpoint, versioning
- **Tags**: Custom tags for all resources

## Outputs

After apply, outputs include cluster endpoints, secret ARNs (MQ and RDS passwords), and `configure_kubectl` for cluster access.
