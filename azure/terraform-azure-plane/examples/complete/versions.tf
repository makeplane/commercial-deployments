terraform {
  required_version = ">= 1.10"

  # Exact versions here; the module itself only sets lower bounds.
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.12.0"
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

  # State holds generated secrets (database and RabbitMQ passwords, the Redis key, app keys), so it
  # lives in a private storage account with Entra ID auth. Settings come from backend.hcl (see
  # backend.hcl.example):
  #   terraform init -backend-config=backend.hcl
  backend "azurerm" {}
}
