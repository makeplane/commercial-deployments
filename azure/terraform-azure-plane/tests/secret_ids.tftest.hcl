# Customer Key Vault certificate IDs (web and email) and cluster admin object IDs: checked at plan. A certificate
# ID must be a full, versionless resource ID in this subscription; anything else would fail at sync time.
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
      storage_account_name   = "planetestabcd1234"
      storage_container_name = "uploads"
      storage_container_id   = "/subscriptions/mock/resourceGroups/plane-test-rg/providers/Microsoft.Storage/storageAccounts/planetestabcd1234/blobServices/default/containers/uploads"
      storage_blob_endpoint  = "https://planetestabcd1234.blob.core.windows.net/"
    }
  }
}

variables {
  name     = "plane-test"
  domain   = "plane.example.com"
  location = "eastus2"

  kv = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/certs-rg/providers/Microsoft.KeyVault/vaults/customer-kv"
}

run "accept_full_ids" {
  variables {
    ingress = { mode = "automated", tls_certificate_secret_id = "${var.kv}/certificates/plane-web" }
    # Secret IDs work too, and ARM IDs may come in any case.
    email                    = { certificate_secret_id = "/SUBSCRIPTIONS/00000000-0000-0000-0000-000000000003/resourcegroups/Certs_RG.(1)/providers/microsoft.keyvault/vaults/Customer-KV/secrets/plane-mail" }
    cluster_admin_object_ids = ["0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0", "AABBCCDD-0000-1111-2222-333344445555"]
  }

  assert {
    condition     = length([for o in yamldecode(output.plane_helm_values).extraObjects : o if o.kind == "ExternalSecret" && endswith(o.metadata.name, "-tls")]) == 2
    error_message = "Valid web and email certificate IDs must both be synced."
  }
}

run "reject_web_other_subscription" {
  command = plan
  variables {
    ingress = { mode = "automated", tls_certificate_secret_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/certs-rg/providers/Microsoft.KeyVault/vaults/customer-kv/certificates/plane-web" }
  }
  expect_failures = [var.ingress]
}

run "reject_web_versioned" {
  command = plan
  variables {
    ingress = { mode = "automated", tls_certificate_secret_id = "${var.kv}/certificates/plane-web/0123456789abcdef0123456789abcdef" }
  }
  expect_failures = [var.ingress]
}

run "reject_web_vault_url" {
  command = plan
  variables {
    ingress = { mode = "automated", tls_certificate_secret_id = "https://customer-kv.vault.azure.net/certificates/plane-web" }
  }
  expect_failures = [var.ingress]
}

run "reject_web_key_object" {
  command = plan
  variables {
    ingress = { mode = "automated", tls_certificate_secret_id = "${var.kv}/keys/plane-web" }
  }
  expect_failures = [var.ingress]
}

run "reject_web_bad_vault_name" {
  command = plan
  variables {
    ingress = { mode = "automated", tls_certificate_secret_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/certs-rg/providers/Microsoft.KeyVault/vaults/customer_kv/certificates/plane-web" }
  }
  expect_failures = [var.ingress]
}

run "reject_web_trailing_slash" {
  command = plan
  variables {
    ingress = { mode = "automated", tls_certificate_secret_id = "${var.kv}/certificates/plane-web/" }
  }
  expect_failures = [var.ingress]
}

run "reject_email_other_subscription" {
  command = plan
  variables {
    email = { certificate_secret_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/certs-rg/providers/Microsoft.KeyVault/vaults/customer-kv/certificates/plane-mail" }
  }
  expect_failures = [var.email]
}

run "reject_email_not_a_guid" {
  command = plan
  variables {
    email = { certificate_secret_id = "/subscriptions/my-sub/resourceGroups/certs-rg/providers/Microsoft.KeyVault/vaults/customer-kv/certificates/plane-mail" }
  }
  expect_failures = [var.email]
}

run "reject_email_wrong_provider" {
  command = plan
  variables {
    email = { certificate_secret_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/certs-rg/providers/Microsoft.Storage/vaults/customer-kv/certificates/plane-mail" }
  }
  expect_failures = [var.email]
}

run "reject_admin_not_a_guid" {
  command = plan
  variables {
    cluster_admin_object_ids = ["ops@example.com"]
  }
  expect_failures = [var.cluster_admin_object_ids]
}
