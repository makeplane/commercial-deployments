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
}

run "path_b_default" {
  assert {
    condition     = output.load_balancer_ip == null && output.dns_records.web == null
    error_message = "Path B must not have a Traefik load balancer or a web record."
  }
  assert {
    condition     = output.dns_records.email_host.value == "20.0.0.10" && output.dns_records.email_host.name == "intake.plane.example.com"
    error_message = "The email load balancer (on by default) must give an A record for smtp_domain on its static IP."
  }
  assert {
    condition     = output.dns_records.email_mx.type == "MX" && output.dns_records.email_mx.value == "10 intake.plane.example.com"
    error_message = "The MX record must point at smtp_domain (which has its own A record)."
  }
  assert {
    condition     = output.redis_endpoint == "plane-test-redis.eastus2.redis.azure.net:10000"
    error_message = "redis_endpoint must be host:port, as on AWS and GCP."
  }
  assert {
    condition     = !yamldecode(output.plane_helm_values).ingress.enabled
    error_message = "Path B must not install Plane's routes."
  }
  assert {
    condition     = !contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.kind], "ClusterIssuer")
    error_message = "Path B must not issue certificates."
  }
}

run "a1_lets_encrypt" {
  variables {
    ingress    = { mode = "automated" }
    acme_email = "ops@example.com"
  }

  # No email certificate: a warning, not an error.
  expect_failures = [check.email_certificate]

  assert {
    condition     = output.load_balancer_ip == "20.0.0.10"
    error_message = "Path A (internet-facing) must expose Traefik's static public IP."
  }
  assert {
    condition     = output.dns_records.web.type == "A" && output.dns_records.web.value == output.load_balancer_ip && output.dns_records.web.name == "plane.example.com"
    error_message = "Path A must give an A record for domain on the load balancer IP."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).ingress.enabled
    error_message = "Path A must install Plane's routes."
  }
  assert {
    condition     = contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.kind], "ClusterIssuer")
    error_message = "A.1 must issue the web certificate with cert-manager."
  }
  assert {
    condition     = !contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.metadata.name], "plane-web-tls")
    error_message = "A.1 must not read a web certificate from Key Vault."
  }
}

run "a2_own_certificates" {
  variables {
    ingress = { mode = "automated", tls_certificate_secret_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/certs-rg/providers/Microsoft.KeyVault/vaults/Customer-KV/certificates/plane-web" }
    email   = { certificate_secret_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/certs-rg/providers/Microsoft.KeyVault/vaults/customer-kv/certificates/plane-mail" }
  }

  assert {
    condition     = output.load_balancer_ip == "20.0.0.10"
    error_message = "Path A must expose Traefik's static public IP."
  }
  assert {
    condition = alltrue([
      for n in ["plane-web-tls", "plane-mail-tls"] :
      contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.metadata.name], n)
    ])
    error_message = "A.2 must sync the web and email certificates from Key Vault."
  }
  assert {
    condition = length([
      for o in yamldecode(output.plane_helm_values).extraObjects : o
      if o.kind == "SecretStore" && try(o.spec.provider.azurekv.vaultUrl, "") == "https://customer-kv.vault.azure.net/"
    ]) == 1
    error_message = "Certificates in one customer vault need exactly one SecretStore for that vault (name compared case-insensitively)."
  }
  assert {
    condition = [
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.data[0].remoteRef.key
      if o.metadata.name == "plane-web-tls"
    ] == ["secret/plane-web"]
    error_message = "The web certificate must be read from the certificate's backing secret."
  }
  assert {
    condition     = !contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.kind], "ClusterIssuer")
    error_message = "A.2 must not use Let's Encrypt."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).services.email_service.tls_secret_name == "plane-mail-tls-secret"
    error_message = "The email service must use the synced email certificate."
  }
}

run "a2_internal" {
  variables {
    ingress = {
      mode                      = "automated"
      scheme                    = "internal"
      allowed_cidrs             = ["10.0.0.0/8"]
      tls_certificate_secret_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/certs-rg/providers/Microsoft.KeyVault/vaults/customer-kv/certificates/plane-web"
    }
  }

  expect_failures = [check.email_certificate]

  assert {
    condition     = output.load_balancer_ip == cidrhost(cidrsubnet("10.60.0.0/16", 4, 0), -10)
    error_message = "An internal Traefik load balancer must use the fixed private IP near the end of the AKS subnet."
  }
  assert {
    condition     = output.dns_records.web.value == output.load_balancer_ip
    error_message = "The web record must point at the internal IP."
  }
}

run "path_b_email_certificate" {
  variables {
    email = { certificate_secret_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/certs-rg/providers/Microsoft.KeyVault/vaults/customer-kv/certificates/plane-mail" }
  }

  assert {
    condition     = contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.metadata.name], "plane-mail-tls")
    error_message = "The email certificate must be synced in path B too."
  }
  assert {
    condition     = !contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.metadata.name], "plane-web-tls")
    error_message = "Path B never syncs a web certificate."
  }
}

run "reject_unknown_mode" {
  command = plan
  variables {
    ingress = { mode = "nginx" }
  }
  expect_failures = [var.ingress]
}

run "reject_automated_without_certificate" {
  command = plan
  variables {
    ingress = { mode = "automated" }
  }
  expect_failures = [var.ingress]
}

run "reject_automated_with_both_certificates" {
  command = plan
  variables {
    ingress    = { mode = "automated", tls_certificate_secret_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/certs-rg/providers/Microsoft.KeyVault/vaults/customer-kv/certificates/plane-web" }
    acme_email = "ops@example.com"
  }
  expect_failures = [var.ingress]
}

run "reject_lets_encrypt_restricted" {
  command = plan
  variables {
    ingress    = { mode = "automated", allowed_cidrs = ["203.0.113.0/24"] }
    acme_email = "ops@example.com"
  }
  expect_failures = [var.ingress]
}

run "reject_lets_encrypt_internal" {
  command = plan
  variables {
    ingress    = { mode = "automated", scheme = "internal" }
    acme_email = "ops@example.com"
  }
  expect_failures = [var.ingress]
}

run "reject_certificate_uri" {
  command = plan
  variables {
    ingress = { mode = "automated", tls_certificate_secret_id = "https://customer-kv.vault.azure.net/certificates/plane-web" }
  }
  expect_failures = [var.ingress]
}

run "reject_pi" {
  command = plan
  variables {
    enable_components = { pi = true }
  }
  expect_failures = [var.enable_components]
}

run "email_off" {
  variables {
    email = { enabled = false }
  }

  assert {
    condition     = output.dns_records.email_mx == null && output.dns_records.email_host == null && output.email_load_balancer_ip == null
    error_message = "email.enabled = false must turn off the email load balancer too."
  }
}
