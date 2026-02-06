# VPC Module

Creates a VPC with public and private subnets, Internet Gateway, and NAT Gateway(s) for private subnet internet egress.

## Features

- VPC with configurable CIDR
- Public subnets with auto-assign public IP
- Private subnets for EKS
- Internet Gateway for public subnets
- NAT Gateway (single or per-AZ)
- EKS-compatible subnet tagging

## Usage

This module is typically used by the root module. For standalone usage:

```hcl
module "vpc" {
  source = "./modules/vpc"

  cluster_name         = "my-cluster"
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-west-2a", "us-west-2b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  single_nat_gateway   = true
}
```
