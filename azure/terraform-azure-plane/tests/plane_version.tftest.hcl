# plane_version floors: the Azure Blob storage backend (always) and Plane AI (with enable_components.pi).
mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      object_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000003"
    }
  }
  mock_resource "azurerm_public_ip" {
    defaults = { ip_address = "20.0.0.10" }
  }
  mock_resource "azurerm_resource_group" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/plane-test-rg" }
  }
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/plane-test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock"
      client_id    = "00000000-0000-0000-0000-00000000000c"
      principal_id = "00000000-0000-0000-0000-00000000000a"
    }
  }
}
mock_provider "helm" {}
mock_provider "random" {}
mock_provider "time" {}

# Only the edge logic is under test; the other layers return fixed outputs.
override_module {
  target = module.network
  outputs = {
    vnet_id                     = "/subscriptions/mock/resourceGroups/plane-test-rg/providers/Microsoft.Network/virtualNetworks/plane-test-vnet"
    aks_subnet_id               = "/subscriptions/mock/resourceGroups/plane-test-rg/providers/Microsoft.Network/virtualNetworks/plane-test-vnet/subnets/aks"
    postgres_subnet_id          = "/subscriptions/mock/resourceGroups/plane-test-rg/providers/Microsoft.Network/virtualNetworks/plane-test-vnet/subnets/postgres"
    private_endpoints_subnet_id = "/subscriptions/mock/resourceGroups/plane-test-rg/providers/Microsoft.Network/virtualNetworks/plane-test-vnet/subnets/pe"
    nat_public_ip               = "20.0.0.1"
  }
}

override_module {
  target = module.cluster
  outputs = {
    cluster_name                       = "plane-test"
    cluster_id                         = "/subscriptions/mock/resourceGroups/plane-test-rg/providers/Microsoft.ContainerService/managedClusters/plane-test"
    cluster_endpoint                   = "https://plane-test.hcp.eastus2.azmk8s.io:443"
    cluster_certificate_authority_data = "bW9jaw=="
    oidc_issuer_url                    = "https://eastus2.oic.prod-aks.azure.com/tenant/issuer/"
    node_resource_group                = "plane-test-rg-plane-test-nodes"
    ready                              = "plane-test"
  }
}

override_module {
  target = module.data
  outputs = {
    postgres_host          = "plane-test-pg.postgres.database.azure.com"
    redis_host             = "plane-test-redis.eastus2.redis.azure.net"
    key_vault_id           = "/subscriptions/mock/resourceGroups/plane-test-rg/providers/Microsoft.KeyVault/vaults/plane-test-kv"
    key_vault_uri          = "https://plane-test-kv.vault.azure.net/"
    storage_account_name   = "planetestabcd1234"
    storage_container_name = "uploads"
    secret_ids             = {}
    plane_inputs = {
      key_vault_uri          = "https://plane-test-kv.vault.azure.net/"
      postgres_host          = "plane-test-pg.postgres.database.azure.com"
      postgres_port          = 5432
      postgres_db            = "plane"
      postgres_secret_name   = "plane-db"
      redis_host             = "plane-test-redis.eastus2.redis.azure.net"
      redis_port             = 10000
      redis_secret_name      = "plane-redis"
      rabbitmq_secret_name   = "plane-rabbitmq"
      opensearch_secret_name = "plane-opensearch"
      app_keys_secret_name   = "plane-app-keys"
      app_key_names          = ["AES_SECRET_KEY", "SECRET_KEY"]
      storage_account_name   = "planetestabcd1234"
      storage_container_name = "uploads"
      storage_container_id   = "/subscriptions/mock/resourceGroups/plane-test-rg/providers/Microsoft.Storage/storageAccounts/planetestabcd1234/blobServices/default/containers/uploads"
      storage_blob_endpoint  = "https://planetestabcd1234.blob.core.windows.net/"
    }
  }
}


# No plane_version here: the first run plans with the module's default.
variables {
  name     = "plane-test"
  domain   = "plane.example.com"
  location = "eastus2"

  openai_key = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/keys-rg/providers/Microsoft.KeyVault/vaults/plane-keys-kv/secrets/plane-openai-key"
  cohere_key = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/keys-rg/providers/Microsoft.KeyVault/vaults/plane-keys-kv/secrets/plane-cohere-key"
}

run "reject_default_plane_version" {
  command         = plan
  expect_failures = [var.plane_version]
}

run "reject_release_below_blob_floor" {
  command = plan
  variables {
    plane_version = "v4.2.0"
  }
  expect_failures = [var.plane_version]
}

run "reject_suffixed_release_below_blob_floor" {
  command = plan
  variables {
    plane_version = "v4.0.1-rc.1"
  }
  expect_failures = [var.plane_version]
}

# Branch and preview builds aren't releases: neither floor checks them (the same rule as pi's).
run "branch_build_tag_not_checked" {
  variables {
    plane_version = "featINFRA-1261-azure-blob"
  }

  assert {
    condition     = yamldecode(output.plane_helm_values).planeVersion == "featINFRA-1261-azure-blob"
    error_message = "A branch build tag must pass the Blob floor and reach the chart as is."
  }
}

run "branch_build_tag_with_pi" {
  variables {
    plane_version     = "featINFRA-1261-azure-blob"
    enable_components = { pi = true }
    pi                = { api_keys = { chat_key_secret_id = var.openai_key, embedding_key_secret_id = var.cohere_key } }
  }
}

run "accept_release_at_blob_floor" {
  variables {
    plane_version = "v99.0.0"
  }

  assert {
    condition     = yamldecode(output.plane_helm_values).planeVersion == "v99.0.0" && yamldecode(output.plane_helm_values).env.storage_provider == "AZURE"
    error_message = "A release at the floor must be accepted with Azure Blob storage."
  }
}

run "accept_release_above_blob_floor" {
  variables {
    plane_version = "v99.1.0"
  }
}
