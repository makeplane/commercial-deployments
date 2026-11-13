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
  chat_key   = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/keys-rg/providers/Microsoft.KeyVault/vaults/customer-kv/secrets/plane-chat-key"
  ai_keys    = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/keys-rg/providers/Microsoft.KeyVault/vaults/customer-kv/secrets/plane-ai-keys"
}

# The api sizes its search indexes with the embedding model's dimension, so it is rendered with pi off too.
run "embedding_dimension_default_pi_off" {
  assert {
    condition = one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.target.template.data.OPENSEARCH_EMBEDDING_DIMENSION if o.metadata.name == "plane-opensearch"
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
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.target.template.data.OPENSEARCH_EMBEDDING_DIMENSION if o.metadata.name == "plane-opensearch"
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
    condition = yamldecode(output.plane_helm_values).services.pi.ai_providers == {
      embedding_model = { enabled = true, name = "cohere/embed-v4.0", embedding_dimension = 1536 }
    }
    error_message = "Plane AI must embed with cohere/embed-v4.0 at 1536 dimensions by default, with no custom LLM (an OpenAI key)."
  }
  assert {
    condition = one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.target.template.data.OPENSEARCH_EMBEDDING_DIMENSION if o.metadata.name == "plane-opensearch"
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
    error_message = "External Secrets must copy each plain-text key, by name, into the env var pi reads: an OpenAI key and Cohere by default."
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

run "pi_vendor_anthropic" {
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
    error_message = "A anthropic key must reach pi as CLAUDE_API_KEY."
  }
  assert {
    condition     = !can(yamldecode(output.plane_helm_values).services.pi.ai_providers.custom_llm)
    error_message = "A vendor key needs no custom LLM."
  }
}

run "pi_vendor_xai" {
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi                = { api_keys = { chat_provider = "xai", chat_key_secret_id = var.chat_key, embedding_key_secret_id = var.cohere_key } }
  }

  assert {
    condition = toset(one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.data if o.metadata.name == "plane-ai-providers"
      ])) == toset([
      { secretKey = "XAI_API_KEY", remoteRef = { key = "secret/plane-chat-key" } },
      { secretKey = "COHERE_API_KEY", remoteRef = { key = "secret/plane-cohere-key" } },
    ])
    error_message = "A xai key must reach pi as XAI_API_KEY."
  }
  assert {
    condition     = !can(yamldecode(output.plane_helm_values).services.pi.ai_providers.custom_llm)
    error_message = "A vendor key needs no custom LLM."
  }
}

run "pi_vendor_baseten" {
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi                = { api_keys = { chat_provider = "baseten", chat_key_secret_id = var.chat_key, embedding_key_secret_id = var.cohere_key } }
  }

  assert {
    condition = toset(one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.data if o.metadata.name == "plane-ai-providers"
      ])) == toset([
      { secretKey = "BASETEN_API_KEY", remoteRef = { key = "secret/plane-chat-key" } },
      { secretKey = "COHERE_API_KEY", remoteRef = { key = "secret/plane-cohere-key" } },
    ])
    error_message = "A baseten key must reach pi as BASETEN_API_KEY."
  }
  assert {
    condition     = !can(yamldecode(output.plane_helm_values).services.pi.ai_providers.custom_llm)
    error_message = "A vendor key needs no custom LLM."
  }
}

run "pi_vendor_meta" {
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi                = { api_keys = { chat_provider = "meta", chat_key_secret_id = var.chat_key, embedding_key_secret_id = var.cohere_key } }
  }

  assert {
    condition = toset(one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.data if o.metadata.name == "plane-ai-providers"
      ])) == toset([
      { secretKey = "META_API_KEY", remoteRef = { key = "secret/plane-chat-key" } },
      { secretKey = "COHERE_API_KEY", remoteRef = { key = "secret/plane-cohere-key" } },
    ])
    error_message = "A meta key must reach pi as META_API_KEY."
  }
  assert {
    condition     = !can(yamldecode(output.plane_helm_values).services.pi.ai_providers.custom_llm)
    error_message = "A vendor key needs no custom LLM."
  }
}

run "pi_custom_json_fields" {
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi = {
      api_keys = {
        chat_provider            = "custom"
        chat_base_url            = "https://my-resource.openai.azure.com/openai/v1"
        chat_model               = "gpt-5-1-deployment"
        chat_model_name          = "GPT-5.1 (Azure OpenAI)"
        chat_max_tokens          = 64000
        chat_key_secret_id       = var.ai_keys
        chat_key_json_field      = "chat_key"
        embedding_model          = "cohere/embed-english-v3.0"
        embedding_key_secret_id  = var.ai_keys
        embedding_key_json_field = "cohere_key"
      }
    }
  }

  assert {
    condition = toset(one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.data if o.metadata.name == "plane-ai-providers"
      ])) == toset([
      { secretKey = "CUSTOM_LLM_API_KEY", remoteRef = { key = "secret/plane-ai-keys", property = "chat_key" } },
      { secretKey = "COHERE_API_KEY", remoteRef = { key = "secret/plane-ai-keys", property = "cohere_key" } },
    ])
    error_message = "One JSON secret for both keys: each read from its own field, the chat key into CUSTOM_LLM_API_KEY."
  }
  assert {
    condition     = toset([for s in values(local.customer_secrets) : s.secret_scope]) == toset([var.ai_keys])
    error_message = "One JSON secret for both keys: one grant."
  }
  assert {
    condition = yamldecode(output.plane_helm_values).services.pi.ai_providers.custom_llm == {
      enabled    = true, provider = "openai", base_url = "https://my-resource.openai.azure.com/openai/v1"
      model_key  = "gpt-5-1-deployment", name = "GPT-5.1 (Azure OpenAI)"
      max_tokens = 64000
    }
    error_message = "The endpoint, model, name and window reach pi's custom LLM, on the OpenAI API."
  }
  assert {
    condition = (
      yamldecode(output.plane_helm_values).services.pi.ai_providers.embedding_model == { enabled = true, name = "cohere/embed-english-v3.0", embedding_dimension = 1024 }
      && one([
        for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.target.template.data.OPENSEARCH_EMBEDDING_DIMENSION if o.metadata.name == "plane-opensearch"
      ]) == "1024"
    )
    error_message = "The embedding model sets pi's model and the search indexes' dimension (1024)."
  }
}

run "pi_custom_defaults" {
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi = {
      api_keys = {
        chat_provider      = "custom", chat_base_url = "http://vllm.internal:8000/v1", chat_model = "openai/gpt-oss-120b"
        chat_key_secret_id = var.chat_key, embedding_key_secret_id = var.cohere_key
      }
    }
  }

  assert {
    condition = yamldecode(output.plane_helm_values).services.pi.ai_providers.custom_llm == {
      enabled    = true, provider = "openai", base_url = "http://vllm.internal:8000/v1", model_key = "openai/gpt-oss-120b", name = "openai/gpt-oss-120b"
      max_tokens = 128000
    }
    error_message = "The model's name defaults to its ID, and its window to 128000."
  }
  assert {
    condition = toset(one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.data if o.metadata.name == "plane-ai-providers"
      ])) == toset([
      { secretKey = "CUSTOM_LLM_API_KEY", remoteRef = { key = "secret/plane-chat-key" } },
      { secretKey = "COHERE_API_KEY", remoteRef = { key = "secret/plane-cohere-key" } },
    ])
    error_message = "Plain-text secrets: each key whole, with no JSON property."
  }
}

run "pi_embedding_dimension_follows_model" {
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi = {
      api_keys = { chat_key_secret_id = var.openai_key, embedding_model = "cohere/embed-english-v2.0", embedding_key_secret_id = var.cohere_key }
    }
  }

  assert {
    condition     = yamldecode(output.plane_helm_values).services.pi.ai_providers.embedding_model == { enabled = true, name = "cohere/embed-english-v2.0", embedding_dimension = 4096 }
    error_message = "Plane AI must embed with the chosen model at its dimension (4096)."
  }
  assert {
    condition = one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.target.template.data.OPENSEARCH_EMBEDDING_DIMENSION if o.metadata.name == "plane-opensearch"
    ]) == "4096"
    error_message = "The OpenSearch Secret must carry the chosen model's dimension (4096)."
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

run "reject_openai_embeddings" {
  command = plan
  variables {
    pi = {
      api_keys = { chat_key_secret_id = var.openai_key, embedding_model = "openai/text-embedding-3-small", embedding_key_secret_id = var.openai_key }
    }
  }
  expect_failures = [var.pi]
}

run "reject_vendor_with_chat_base_url" {
  command = plan
  variables {
    pi = { api_keys = { chat_base_url = "https://my-resource.openai.azure.com/openai/v1", chat_key_secret_id = var.openai_key, embedding_key_secret_id = var.cohere_key } }
  }
  expect_failures = [var.pi]
}

run "reject_vendor_with_chat_model" {
  command = plan
  variables {
    pi = { api_keys = { chat_provider = "anthropic", chat_model = "claude-sonnet-4-6", chat_key_secret_id = var.claude_key, embedding_key_secret_id = var.cohere_key } }
  }
  expect_failures = [var.pi]
}

run "reject_vendor_with_chat_max_tokens" {
  command = plan
  variables {
    pi = { api_keys = { chat_provider = "xai", chat_max_tokens = 128000, chat_key_secret_id = var.chat_key, embedding_key_secret_id = var.cohere_key } }
  }
  expect_failures = [var.pi]
}

run "reject_custom_without_base_url" {
  command = plan
  variables {
    pi = { api_keys = { chat_provider = "custom", chat_model = "gpt-5.1", chat_key_secret_id = var.chat_key, embedding_key_secret_id = var.cohere_key } }
  }
  expect_failures = [var.pi]
}

run "reject_custom_bad_base_url" {
  command = plan
  variables {
    pi = {
      api_keys = { chat_provider = "custom", chat_base_url = "my-resource.openai.azure.com/openai/v1", chat_model = "gpt-5.1", chat_key_secret_id = var.chat_key, embedding_key_secret_id = var.cohere_key }
    }
  }
  expect_failures = [var.pi]
}

run "reject_custom_without_model" {
  command = plan
  variables {
    pi = {
      api_keys = { chat_provider = "custom", chat_base_url = "https://llm.example.com/v1", chat_key_secret_id = var.chat_key, embedding_key_secret_id = var.cohere_key }
    }
  }
  expect_failures = [var.pi]
}

run "reject_custom_blank_model" {
  command = plan
  variables {
    pi = {
      api_keys = { chat_provider = "custom", chat_base_url = "https://llm.example.com/v1", chat_model = " ", chat_key_secret_id = var.chat_key, embedding_key_secret_id = var.cohere_key }
    }
  }
  expect_failures = [var.pi]
}

run "reject_small_chat_max_tokens" {
  command = plan
  variables {
    pi = {
      api_keys = {
        chat_provider      = "custom", chat_base_url = "https://llm.example.com/v1", chat_model = "my-model", chat_max_tokens = 10
        chat_key_secret_id = var.chat_key, embedding_key_secret_id = var.cohere_key
      }
    }
  }
  expect_failures = [var.pi]
}

run "reject_fractional_chat_max_tokens" {
  command = plan
  variables {
    pi = {
      api_keys = {
        chat_provider      = "custom", chat_base_url = "https://llm.example.com/v1", chat_model = "my-model", chat_max_tokens = 64000.5
        chat_key_secret_id = var.chat_key, embedding_key_secret_id = var.cohere_key
      }
    }
  }
  expect_failures = [var.pi]
}

run "reject_bad_json_field" {
  command = plan
  variables {
    pi = { api_keys = { chat_key_secret_id = var.ai_keys, chat_key_json_field = "open ai", embedding_key_secret_id = var.ai_keys, embedding_key_json_field = "cohere_key" } }
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
    pi = { api_keys = { chat_provider = "azure_openai" } }
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
