config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.30.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Data resources are protected with Azure CanNotDelete locks driven by inputs (postgres.deletion_protection,
# storage.deletion_protection), so a deliberate destroy can turn them off. prevent_destroy can't take a variable.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
