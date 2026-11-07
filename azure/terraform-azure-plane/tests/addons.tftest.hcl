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

variables {
  name                   = "plane-test"
  location               = "eastus2"
  resource_group_name    = "plane-test-rg"
  tenant_id              = "00000000-0000-0000-0000-000000000001"
  oidc_issuer_url        = "https://eastus2.oic.prod-aks.azure.com/tenant/issuer/"
  install_traefik        = true
  allowed_cidrs          = ["0.0.0.0/0"]
  load_balancer_scheme   = "internet-facing"
  ingress_public_ip_name = "plane-test-ingress-pip"
  internal_ingress_ip    = "10.60.15.246"
  issue_certificate      = false
  key_vault_id           = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/plane-test-rg/providers/Microsoft.KeyVault/vaults/plane-test-kv"
  customer_secret_scopes = []
  cluster_ready          = "plane-test"
  tags                   = {}
}

run "internet_facing_static_ip" {
  command = plan
  module {
    source = "./modules/addons"
  }

  assert {
    condition     = yamldecode(helm_release.traefik[0].values[0]).service.annotations["service.beta.kubernetes.io/azure-pip-name"] == "plane-test-ingress-pip"
    error_message = "An internet-facing Traefik load balancer must use the module's static public IP."
  }
  assert {
    condition     = yamldecode(helm_release.traefik[0].values[0]).service.annotations["service.beta.kubernetes.io/azure-load-balancer-resource-group"] == "plane-test-rg"
    error_message = "The public IP lives in the deployment's resource group, not the node resource group."
  }
  assert {
    condition     = !contains(keys(yamldecode(helm_release.traefik[0].values[0]).service.annotations), "service.beta.kubernetes.io/azure-load-balancer-internal")
    error_message = "An internet-facing load balancer must not be internal."
  }
  assert {
    condition     = yamldecode(helm_release.traefik[0].values[0]).service.annotations["service.beta.kubernetes.io/azure-load-balancer-tcp-idle-timeout"] == "30"
    error_message = "The load balancer idle timeout must cover live's websockets (30 minutes)."
  }
  assert {
    condition     = yamldecode(helm_release.traefik[0].values[0]).service.spec.externalTrafficPolicy == "Local"
    error_message = "Traefik must see the client IP (externalTrafficPolicy: Local)."
  }
  assert {
    condition     = yamldecode(helm_release.traefik[0].values[0]).service.spec.loadBalancerSourceRanges == ["0.0.0.0/0"]
    error_message = "ingress.allowed_cidrs must reach loadBalancerSourceRanges."
  }
  assert {
    condition     = length(helm_release.cert_manager) == 0
    error_message = "No cert-manager without Let's Encrypt."
  }
}

run "internal_fixed_ip" {
  command = plan
  module {
    source = "./modules/addons"
  }
  variables {
    load_balancer_scheme   = "internal"
    ingress_public_ip_name = null
    allowed_cidrs          = ["10.0.0.0/8"]
  }

  assert {
    condition     = yamldecode(helm_release.traefik[0].values[0]).service.annotations["service.beta.kubernetes.io/azure-load-balancer-internal"] == "true"
    error_message = "An internal Traefik load balancer must be internal."
  }
  assert {
    condition     = yamldecode(helm_release.traefik[0].values[0]).service.annotations["service.beta.kubernetes.io/azure-load-balancer-ipv4"] == "10.60.15.246"
    error_message = "An internal Traefik load balancer must use the fixed private IP."
  }
  assert {
    condition     = !contains(keys(yamldecode(helm_release.traefik[0].values[0]).service.annotations), "service.beta.kubernetes.io/azure-pip-name")
    error_message = "An internal load balancer must not take a public IP."
  }
}

run "path_b_no_traefik" {
  command = plan
  module {
    source = "./modules/addons"
  }
  variables {
    install_traefik = false
  }

  assert {
    condition     = length(helm_release.traefik) == 0
    error_message = "Path B installs no Traefik."
  }
}

run "external_secrets_workload_identity" {
  module {
    source = "./modules/addons"
  }
  variables {
    issue_certificate = true
    customer_secret_scopes = [
      "/subscriptions/0000/resourceGroups/certs-rg/providers/Microsoft.KeyVault/vaults/customer-kv/secrets/plane-web",
    ]
  }

  assert {
    condition     = yamldecode(helm_release.external_secrets.values[0]).podLabels["azure.workload.identity/use"] == "true"
    error_message = "The External Secrets controller must carry the Workload Identity pod label."
  }
  assert {
    condition     = yamldecode(helm_release.external_secrets.values[0]).serviceAccount.annotations["azure.workload.identity/client-id"] == "00000000-0000-0000-0000-00000000000c"
    error_message = "The External Secrets ServiceAccount must name its managed identity."
  }
  assert {
    condition     = yamldecode(helm_release.external_secrets.values[0]).crds.annotations["helm.sh/resource-policy"] == "keep"
    error_message = "The External Secrets CRDs must be kept on uninstall (hook ExternalSecrets need them to finalize)."
  }
  assert {
    condition     = azurerm_federated_identity_credential.external_secrets.subject == "system:serviceaccount:external-secrets:external-secrets"
    error_message = "The federated credential must trust only the External Secrets controller."
  }
  assert {
    condition     = length(azurerm_role_assignment.external_secrets_certificates) == 1
    error_message = "External Secrets needs read access to each customer certificate."
  }
  assert {
    condition     = length(helm_release.cert_manager) == 1
    error_message = "Let's Encrypt needs cert-manager."
  }
}
