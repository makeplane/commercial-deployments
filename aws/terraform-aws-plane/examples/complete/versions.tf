terraform {
  required_version = ">= 1.10"

  # Exact versions here; the module itself only sets lower bounds.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.71.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.14.2"
    }
  }

  # State holds generated secrets (Valkey AUTH token, MQ password, app keys), so it lives in an
  # encrypted, private S3 bucket. Settings come from backend.hcl (see backend.hcl.example):
  #   terraform init -backend-config=backend.hcl
  backend "s3" {}
}
