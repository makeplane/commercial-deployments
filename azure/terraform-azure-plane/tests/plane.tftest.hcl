mock_provider "azurerm" {
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/plane-test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock"
      client_id    = "00000000-0000-0000-0000-00000000000c"
      principal_id = "00000000-0000-0000-0000-00000000000a"
    }
  }
}
mock_provider "helm" {}
mock_provider "time" {}

variables {
  name                  = "plane-test"
  location              = "eastus2"
  resource_group_name   = "plane-test-rg"
  tenant_id             = "00000000-0000-0000-0000-000000000001"
  oidc_issuer_url       = "https://eastus2.oic.prod-aks.azure.com/tenant/issuer/"
  domain                = "plane.example.com"
  plane_version         = "v4.0.1"
  chart_version         = "3.11.5"
  pod_cidr              = "192.168.0.0/16"
  enable_components     = { silo = true, drawio = true, pi = false }
  tls_secret_name       = "plane-tls"
  ingress_enabled       = false
  certificates          = {}
  email                 = { enabled = true, smtp_domain = "intake.plane.example.com", load_balancer = true, certificate_secret_id = null }
  email_public_ip_name  = "plane-test-email-pip"
  chart_repository      = "https://helm.plane.so/"
  chart_name            = "plane-enterprise"
  acme_email            = null
  acme_server           = "https://acme-v02.api.letsencrypt.org/directory"
  rabbitmq              = { mode = "in-cluster", volume_size_gb = 10 }
  opensearch            = { enabled = true, mode = "in-cluster", volume_size_gb = 50, index_prefix = "plane" }
  persistent_volume_sku = "Premium_ZRS"
  helm_timeout          = 3600
  plane_values          = ""
  addons_ready          = "ready"
  tags                  = {}
  data = {
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
    storage_container_id   = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/plane-test-rg/providers/Microsoft.Storage/storageAccounts/planetestabcd1234/blobServices/default/containers/uploads"
    storage_blob_endpoint  = "https://planetestabcd1234.blob.core.windows.net/"
  }
}

# Pins the "AZURE BLOB STORAGE" contract in modules/plane/main.tf; update both together.
run "blob_contract" {
  module {
    source = "./modules/plane"
  }

  assert {
    condition = {
      for k in ["storage_provider", "azure_storage_account_name", "azure_storage_container_name", "azure_storage_blob_endpoint", "use_storage_proxy"] :
      k => yamldecode(output.helm_values).env[k]
      } == {
      storage_provider             = "AZURE"
      azure_storage_account_name   = "planetestabcd1234"
      azure_storage_container_name = "uploads"
      azure_storage_blob_endpoint  = "https://planetestabcd1234.blob.core.windows.net/"
      use_storage_proxy            = true
    }
    error_message = "The chart's Azure Blob values must follow the agreed contract (storage_provider AZURE, account, container, endpoint, proxy-only)."
  }
  assert {
    condition     = !contains(keys(yamldecode(output.helm_values).env), "docstore_bucket")
    error_message = "docstore_bucket must not be set on Azure: pi would read the bucket as S3."
  }
  assert {
    condition     = yamldecode(output.helm_values).serviceAccount.annotations["azure.workload.identity/client-id"] == "00000000-0000-0000-0000-00000000000c"
    error_message = "Plane's ServiceAccount must name its managed identity."
  }
  assert {
    condition     = yamldecode(output.helm_values).serviceAccount.podLabels["azure.workload.identity/use"] == "true"
    error_message = "Plane's pods must carry the Workload Identity label."
  }
  assert {
    condition     = !yamldecode(output.helm_values).services.minio.local_setup
    error_message = "No bundled MinIO: Blob is the only object store."
  }
  assert {
    condition     = length([for k in keys(yamldecode(output.helm_values).env) : k if startswith(k, "aws_")]) == 0
    error_message = "No S3 settings on Azure."
  }
  assert {
    condition     = azurerm_federated_identity_credential.plane.subject == "system:serviceaccount:plane:plane-srv-account"
    error_message = "Plane's federated credential must trust the chart's ServiceAccount only."
  }
  assert {
    condition     = azurerm_role_assignment.plane_blob.scope == var.data.storage_container_id && azurerm_role_assignment.plane_blob.role_definition_name == "Storage Blob Data Contributor"
    error_message = "Plane gets Storage Blob Data Contributor on the uploads container only."
  }
}

run "in_cluster_services" {
  command = plan
  module {
    source = "./modules/plane"
  }

  assert {
    condition     = yamldecode(output.helm_values).services.rabbitmq.local_setup && yamldecode(output.helm_values).external_secrets.rabbitmq.secretName == "plane-rabbitmq"
    error_message = "The bundled RabbitMQ and the apps must read one Secret synced from Key Vault (external_secrets.rabbitmq, chart 3.11.5)."
  }
  assert {
    condition     = !strcontains(output.helm_values, "default_password") && !strcontains(output.helm_values, "root_password")
    error_message = "No secret values in the Helm values."
  }
  assert {
    condition     = yamldecode(output.helm_values).services.rabbitmq.volumeSize == "10Gi" && yamldecode(output.helm_values).services.opensearch.volumeSize == "50Gi"
    error_message = "Volume sizes must follow rabbitmq.volume_size_gb and opensearch.volume_size_gb."
  }
  assert {
    condition = [
      for o in yamldecode(output.helm_values).extraObjects : o.parameters.skuName
      if o.kind == "StorageClass" && o.metadata.name == yamldecode(output.helm_values).env.storageClass
    ] == ["Premium_ZRS"]
    error_message = "The in-cluster services' volumes must use the module's Premium ZRS StorageClass."
  }
  assert {
    condition = [
      for o in yamldecode(output.helm_values).extraObjects : o.spec.provider.azurekv.vaultUrl
      if o.kind == "SecretStore" && o.metadata.name == "azure-key-vault"
    ] == ["https://plane-test-kv.vault.azure.net/"]
    error_message = "External Secrets must read the module's Key Vault (azurekv)."
  }
  # Chart-internal keys (opensearchdb.yaml): pin the list.
  assert {
    condition = toset(flatten([
      for o in yamldecode(output.helm_values).extraObjects : keys(o.spec.target.template.data)
      if o.metadata.name == "plane-opensearch-creds"
      ])) == toset([
      "OPENSEARCH_ENABLED", "OPENSEARCH_URL", "OPENSEARCH_USERNAME", "OPENSEARCH_PASSWORD",
      "OPENSEARCH_INITIAL_ADMIN_PASSWORD", "OPENSEARCH_INDEX_PREFIX", "OPENSEARCH_EMBEDDING_DIMENSION",
    ])
    error_message = "The OpenSearch Secret must carry exactly the chart's opensearch-secrets keys."
  }
  assert {
    condition     = yamldecode(output.helm_values).extraEnv[0] == { name = "TRUSTED_PROXIES", value = "192.168.0.0/16" }
    error_message = "The api must trust Traefik's pods (the pod CIDR) for the client IP."
  }
  assert {
    condition     = yamldecode(output.helm_values).services.email_service.service.annotations["service.beta.kubernetes.io/azure-pip-name"] == "plane-test-email-pip"
    error_message = "The email Service must take the module's static public IP."
  }
}

run "opensearch_off" {
  command = plan
  module {
    source = "./modules/plane"
  }
  variables {
    opensearch = { enabled = false, mode = "in-cluster", volume_size_gb = 50, index_prefix = "plane" }
  }

  assert {
    condition     = !yamldecode(output.helm_values).services.opensearch.local_setup && yamldecode(output.helm_values).external_secrets.opensearch_existingSecret == ""
    error_message = "opensearch.enabled = false must remove the in-cluster OpenSearch and its Secret."
  }
  assert {
    condition     = !contains([for o in yamldecode(output.helm_values).extraObjects : o.metadata.name], "plane-opensearch-creds")
    error_message = "No OpenSearch ExternalSecret without OpenSearch."
  }
}
