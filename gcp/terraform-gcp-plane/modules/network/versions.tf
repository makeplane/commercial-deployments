terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.10"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
