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

  # State holds generated secrets (Valkey AUTH token, MQ password, app keys): keep it in an
  # encrypted, access-restricted backend. Uncomment and fill in before the first apply.
  # backend "s3" {
  #   bucket       = "my-terraform-state"
  #   key          = "plane/terraform.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}
