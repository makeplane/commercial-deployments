terraform {
  required_version = ">= 1.10"

  # Exact versions here; the module itself only sets lower bounds.
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.9.0"
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

  # State holds generated secrets: keep it in a private, versioned bucket.
  #   terraform init -backend-config=backend.hcl
  backend "gcs" {}
}
