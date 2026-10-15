# Plane Commercial Deployments

Deploy [Plane](https://plane.so) Commercial on managed Kubernetes in your own cloud account. For each cloud, a Terraform module provisions the infrastructure Plane needs (the cluster, PostgreSQL, Redis, object storage and secrets), and the guide installs Plane on top of it.

| Cloud | Kubernetes | Guide | Terraform module |
|---|---|---|---|
| **AWS** | EKS | [aws/README.md](aws/README.md) | [aws/terraform](aws/terraform) |
| **Azure** | AKS | [azure/README.md](azure/README.md) | [azure/terraform](azure/terraform) |
| **Google Cloud** | GKE | Coming soon | Coming soon |

## Prerequisites

- **Terraform** >= 1.5: [Download](https://developer.hashicorp.com/terraform/downloads)
- **kubectl**: [Install](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- The CLI for your cloud, logged in: [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) or [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)

Each cloud has a few more account-level requirements, such as permissions, quotas and provider registration. They are listed in its guide.

## Minimal Configuration

Create an empty directory, add a `main.tf` with the block for your cloud, then run:

```bash
terraform init
terraform plan
terraform apply
```

Defaults are used for everything not shown. Each guide lists the full set of inputs.

### AWS

```hcl
module "plane_infra" {
  source = "git::https://github.com/makeplane/commercial-deployments.git//aws/terraform?ref=main"

  cluster_name             = "plane-eks-cluster"
  region                   = "us-west-2" # required
  vpc_cidr                 = "10.0.0.0/16"
  single_nat_gateway       = true
  enable_aws_lb_controller = true # to use aws ALB
  cluster_version          = "1.34"

  tags = {
    Environment = "plane"
  }
}
```

Creates a VPC, EKS, RDS PostgreSQL, ElastiCache Redis, Amazon MQ RabbitMQ, OpenSearch and S3. Next steps: [aws/README.md](aws/README.md).

### Azure

```hcl
module "plane_infra" {
  source = "git::https://github.com/makeplane/commercial-deployments.git//azure/terraform?ref=main"

  name     = "plane-aks" # prefixes every resource; also the AKS cluster name
  location = "eastus2"   # required

  tags = {
    Environment = "plane"
  }
}
```

Creates a VNet, AKS, PostgreSQL Flexible Server, Azure Managed Redis, Blob storage and Key Vault. Next steps: [azure/README.md](azure/README.md).

### Google Cloud

Coming soon.

> **Upgrading from an earlier AWS setup?** The AWS module moved from `//terraform` to `//aws/terraform`. Update the `source` in your configuration and run `terraform init`. The module's inputs, outputs and resource addresses are unchanged, so the next plan should show no changes.

## Deploy Plane

The Terraform modules provision infrastructure only. To run Plane on the cluster, use either:

- **Helm**: the [plane-enterprise chart](https://github.com/makeplane/helm-charts/tree/master/charts/plane-enterprise). The [Azure guide](azure/README.md) wires the chart from the Terraform outputs end to end.
- **Kustomize**: the overlays in [kustomize/](kustomize/README.md). The `managed` overlay connects to the AWS managed services that the AWS module creates.

## Repository layout

```
.
├── aws/
│   ├── README.md      # AWS guide
│   └── terraform/     # AWS module; complete configuration in examples/
├── azure/
│   ├── README.md      # Azure guide
│   ├── examples/      # Helm values and External Secrets manifests for AKS
│   └── terraform/     # Azure module; complete configuration in examples/
└── kustomize/         # Cloud-agnostic Kustomize manifests for the Plane application
```
