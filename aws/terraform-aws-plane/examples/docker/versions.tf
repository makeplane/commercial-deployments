terraform {
  required_version = ">= 1.10"

  # The module requires helm and time too, though Docker mode doesn't use them.
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

  # State holds generated secrets: use an encrypted, private bucket (see ../complete/backend.hcl.example).
  backend "s3" {}
}
