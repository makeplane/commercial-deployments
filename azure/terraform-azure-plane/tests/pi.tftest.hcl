# Plane AI: the keys from a customer Key Vault, OpenSearch sizing, the embedding dimension and the version floor.
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

variables {
  name     = "plane-test"
  domain   = "plane.example.com"
  location = "eastus2"

  kv         = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/keys-rg/providers/Microsoft.KeyVault/vaults/customer-kv"
  openai_key = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/keys-rg/providers/Microsoft.KeyVault/vaults/customer-kv/secrets/plane-openai-key"
  cohere_key = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/keys-rg/providers/Microsoft.KeyVault/vaults/customer-kv/secrets/plane-cohere-key"
  claude_key = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/keys-rg/providers/Microsoft.KeyVault/vaults/customer-kv/secrets/plane-claude-key"
}

# The api sizes its search indexes with the embedding model's dimension, so it is rendered with pi off too.
run "embedding_dimension_default_pi_off" {
  assert {
    condition = one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.target.template.data.OPENSEARCH_EMBEDDING_DIMENSION if o.metadata.name == "plane-opensearch-creds"
    ]) == "1536"
    error_message = "With pi off, the OpenSearch Secret must carry the default model's dimension (cohere/embed-v4.0, 1536)."
  }
  assert {
    condition     = !yamldecode(output.plane_helm_values).services.pi.enabled && !can(yamldecode(output.plane_helm_values).services.pi.ai_providers)
    error_message = "With pi off, no pi providers are rendered."
  }
  assert {
    condition = (
      yamldecode(output.plane_helm_values).external_secrets.ai_providers_existingSecret == ""
      && length([for o in yamldecode(output.plane_helm_values).extraObjects : o if o.metadata.name == "plane-ai-providers"]) == 0
      && length([for o in yamldecode(output.plane_helm_values).extraObjects : o if o.kind == "SecretStore"]) == 1
    )
    error_message = "With pi off, no provider Secret and no extra SecretStore."
  }
  assert {
    condition     = !can(yamldecode(output.plane_helm_values).services.opensearch.javaOpts) && !can(yamldecode(output.plane_helm_values).services.opensearch.memoryLimit)
    error_message = "With pi off, OpenSearch keeps the chart's heap and limit."
  }
}

run "embedding_dimension_follows_model_pi_off" {
  variables {
    pi = { api_keys = { embedding_model = "cohere/embed-english-v3.0" } }
  }

  assert {
    condition = one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.target.template.data.OPENSEARCH_EMBEDDING_DIMENSION if o.metadata.name == "plane-opensearch-creds"
    ]) == "1024"
    error_message = "With pi off, the OpenSearch Secret must carry the chosen model's dimension (cohere/embed-english-v3.0, 1024)."
  }
}

run "pi_on_azure_blob" {
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi                = { api_keys = { chat_key_secret_id = var.openai_key, embedding_key_secret_id = var.cohere_key } }
  }

  assert {
    condition     = yamldecode(output.plane_helm_values).services.pi.enabled && yamldecode(output.plane_helm_values).env.storage_provider == "AZURE"
    error_message = "Plane AI must run, on the Blob container."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).env.pg_pi_db_name == "plane_pi"
    error_message = "Plane AI must use the plane_pi database."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).services.pi.ai_providers.embedding_model == { enabled = true, name = "cohere/embed-v4.0", embedding_dimension = 1536 }
    error_message = "Plane AI must embed with cohere/embed-v4.0 at 1536 dimensions by default."
  }
  assert {
    condition = one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.target.template.data.OPENSEARCH_EMBEDDING_DIMENSION if o.metadata.name == "plane-opensearch-creds"
    ]) == "1536"
    error_message = "The OpenSearch Secret must carry the embedding model's dimension (1536)."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).external_secrets.ai_providers_existingSecret == "plane-ai-providers"
    error_message = "The pi workloads must read the provider keys from the plane-ai-providers Secret."
  }
  assert {
    condition = one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec if o.kind == "ExternalSecret" && o.metadata.name == "plane-ai-providers"
      ]) == {
      refreshInterval = "1h"
      secretStoreRef  = { name = "key-vault-customer-kv", kind = "SecretStore" }
      target          = { name = "plane-ai-providers", creationPolicy = "Orphan" }
      data = [
        { secretKey = "COHERE_API_KEY", remoteRef = { key = "secret/plane-cohere-key" } },
        { secretKey = "OPENAI_API_KEY", remoteRef = { key = "secret/plane-openai-key" } },
      ]
    }
    error_message = "External Secrets must copy each key, by name, into the env var pi reads for its provider: OpenAI chat and Cohere embeddings by default."
  }
  assert {
    condition = one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.provider.azurekv.vaultUrl if o.kind == "SecretStore" && o.metadata.name == "key-vault-customer-kv"
    ]) == "https://customer-kv.vault.azure.net/"
    error_message = "A SecretStore must point at the customer's vault."
  }
  assert {
    condition     = toset([for s in values(local.customer_secrets) : s.secret_scope]) == toset([var.openai_key, var.cohere_key])
    error_message = "External Secrets must be granted read on the two key secrets only."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).services.opensearch.javaOpts == "-Xms1536m -Xmx1536m" && yamldecode(output.plane_helm_values).services.opensearch.memoryLimit == "3Gi"
    error_message = "With Plane AI, OpenSearch gets a 1.5 GB heap in a 3 GiB limit."
  }
}

run "pi_keys_and_certificates_share_a_vault_store" {
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi                = { api_keys = { chat_key_secret_id = var.openai_key, embedding_key_secret_id = var.cohere_key } }
    ingress           = { mode = "automated", tls_certificate_secret_id = "${var.kv}/certificates/plane-web" }
    email             = { enabled = false }
  }

  assert {
    condition     = length([for o in yamldecode(output.plane_helm_values).extraObjects : o if o.kind == "SecretStore" && o.metadata.name == "key-vault-customer-kv"]) == 1
    error_message = "One SecretStore per customer vault."
  }
  assert {
    condition     = length(local.customer_secrets) == 3
    error_message = "External Secrets must read the certificate and the two keys."
  }
}

run "pi_anthropic_chat" {
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi                = { api_keys = { chat_provider = "anthropic", chat_key_secret_id = var.claude_key, embedding_key_secret_id = var.cohere_key } }
  }

  assert {
    condition = toset(one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.data if o.metadata.name == "plane-ai-providers"
      ])) == toset([
      { secretKey = "CLAUDE_API_KEY", remoteRef = { key = "secret/plane-claude-key" } },
      { secretKey = "COHERE_API_KEY", remoteRef = { key = "secret/plane-cohere-key" } },
    ])
    error_message = "Anthropic chat reads its key from CLAUDE_API_KEY."
  }
}

run "pi_openai_both" {
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi = {
      api_keys = { chat_key_secret_id = var.openai_key, embedding_model = "openai/text-embedding-3-small", embedding_key_secret_id = var.openai_key }
    }
  }

  assert {
    condition = (
      one([for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.data if o.metadata.name == "plane-ai-providers"]) == [
        { secretKey = "OPENAI_API_KEY", remoteRef = { key = "secret/plane-openai-key" } },
      ]
      && yamldecode(output.plane_helm_values).services.pi.ai_providers.embedding_model.name == "openai/text-embedding-3-small"
      && length(local.customer_secrets) == 1
    )
    error_message = "OpenAI for both: one key, one grant, and the chosen embedding model."
  }
}

run "pi_embedding_dimension_follows_model" {
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi = {
      api_keys = { chat_key_secret_id = var.openai_key, embedding_model = "openai/text-embedding-3-large", embedding_key_secret_id = var.openai_key }
    }
  }

  assert {
    condition     = yamldecode(output.plane_helm_values).services.pi.ai_providers.embedding_model == { enabled = true, name = "openai/text-embedding-3-large", embedding_dimension = 3072 }
    error_message = "Plane AI must embed with the chosen model at its dimension (3072)."
  }
  assert {
    condition = one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.target.template.data.OPENSEARCH_EMBEDDING_DIMENSION if o.metadata.name == "plane-opensearch-creds"
    ]) == "3072"
    error_message = "The OpenSearch Secret must carry the chosen model's dimension (3072)."
  }
}

run "reject_pi_without_opensearch" {
  command = plan
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi                = { api_keys = { chat_key_secret_id = var.openai_key, embedding_key_secret_id = var.cohere_key } }
    opensearch        = { enabled = false }
  }
  expect_failures = [var.enable_components]
}

run "reject_pi_without_keys" {
  command = plan
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi                = { api_keys = { chat_key_secret_id = var.openai_key } }
  }
  expect_failures = [var.pi]
}

run "reject_pi_below_plane_version_floor" {
  command = plan
  variables {
    enable_components = { pi = true }
    pi                = { api_keys = { chat_key_secret_id = var.openai_key, embedding_key_secret_id = var.cohere_key } }
  }
  expect_failures = [var.plane_version]
}

run "pi_on_preview_build_tag" {
  command = plan
  variables {
    enable_components = { pi = true }
    plane_version     = "preview-abc1234"
    pi                = { api_keys = { chat_key_secret_id = var.openai_key, embedding_key_secret_id = var.cohere_key } }
  }
}

run "reject_openai_two_keys" {
  command = plan
  variables {
    pi = {
      api_keys = { chat_key_secret_id = var.openai_key, embedding_model = "openai/text-embedding-3-small", embedding_key_secret_id = var.cohere_key }
    }
  }
  expect_failures = [var.pi]
}

run "reject_keys_in_two_vaults" {
  command = plan
  variables {
    pi = {
      api_keys = {
        chat_key_secret_id      = var.openai_key
        embedding_key_secret_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/keys-rg/providers/Microsoft.KeyVault/vaults/other-kv/secrets/plane-cohere-key"
      }
    }
  }
  expect_failures = [var.pi]
}

run "reject_key_in_another_subscription" {
  command = plan
  variables {
    pi = {
      api_keys = {
        chat_key_secret_id      = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/keys-rg/providers/Microsoft.KeyVault/vaults/customer-kv/secrets/plane-openai-key"
        embedding_key_secret_id = var.cohere_key
      }
    }
  }
  expect_failures = [var.pi]
}

run "reject_key_as_a_certificate_id" {
  command = plan
  variables {
    pi = { api_keys = { chat_key_secret_id = "${var.kv}/certificates/plane-openai-key", embedding_key_secret_id = var.cohere_key } }
  }
  expect_failures = [var.pi]
}

run "reject_versioned_key" {
  command = plan
  variables {
    pi = { api_keys = { chat_key_secret_id = "${var.openai_key}/0123456789abcdef", embedding_key_secret_id = var.cohere_key } }
  }
  expect_failures = [var.pi]
}

run "reject_key_vault_url" {
  command = plan
  variables {
    pi = { api_keys = { chat_key_secret_id = "https://customer-kv.vault.azure.net/secrets/plane-openai-key", embedding_key_secret_id = var.cohere_key } }
  }
  expect_failures = [var.pi]
}

run "reject_bad_chat_provider" {
  command = plan
  variables {
    pi = { api_keys = { chat_provider = "groq" } }
  }
  expect_failures = [var.pi]
}

run "reject_bad_embedding_model" {
  command = plan
  variables {
    pi = { api_keys = { embedding_model = "bedrock/amazon.titan-embed-text-v2" } }
  }
  expect_failures = [var.pi]
}
