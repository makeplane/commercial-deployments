terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.6"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
