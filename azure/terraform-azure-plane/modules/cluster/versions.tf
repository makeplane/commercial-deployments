terraform {
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.12"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
