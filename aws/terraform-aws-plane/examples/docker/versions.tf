terraform {
  required_version = ">= 1.10"

  # Exact versions here (same as examples/complete); the module itself only sets lower bounds. Docker mode
  # configures only the AWS provider: the module also requires helm and time, which it doesn't use in this mode.
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

  # State holds generated secrets (app keys, database, queue and MinIO passwords): keep it in an encrypted,
  # private S3 bucket. terraform init -backend-config=backend.hcl (see ../complete/backend.hcl.example).
  backend "s3" {}
}
