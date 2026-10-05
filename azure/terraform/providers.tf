provider "azurerm" {
  # Falls back to ARM_SUBSCRIPTION_ID / the Azure CLI default subscription when null.
  subscription_id = var.subscription_id

  # The storage account has shared-key auth disabled, so any data-plane call the
  # provider makes must use Entra ID.
  storage_use_azuread = true

  features {
    resource_group {
      # Never delete a resource group that still holds resources Terraform does
      # not manage (e.g. a disk a PVC left behind).
      prevent_deletion_if_contains_resources = true
    }
  }
}
