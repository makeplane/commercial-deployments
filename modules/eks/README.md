# EKS Module

Creates an EKS cluster with managed node groups and essential add-ons in private subnets.

## Features

- EKS cluster with configurable Kubernetes version
- Managed node group with auto-scaling
- EKS add-ons: vpc-cni, kube-proxy, coredns
- IAM roles for cluster and nodes
- Security groups for cluster-node communication
- Optional SSH access to nodes

## Usage

This module is typically used by the root module. For standalone usage:

```hcl
module "eks" {
  source = "./modules/eks"

  cluster_name        = "my-cluster"
  cluster_version    = "1.28"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  node_instance_types = ["t3.medium"]
  node_desired_size  = 2
}
```
