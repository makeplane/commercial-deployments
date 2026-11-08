# AKS ships metrics-server and LB integration, so unlike AWS neither is installed here.

locals {
  external_secrets_namespace = "external-secrets"
  external_secrets_sa        = "external-secrets"
  cert_manager_namespace     = "cert-manager"
  cert_manager_sa            = "cert-manager"

  # HTTP-01 through Traefik: cert-manager needs no Azure access and touches no DNS.
  cert_manager_enabled = var.issue_certificate

  chart_versions = {
    traefik          = "42.3.1"
    cert_manager     = "v1.21.3"
    external_secrets = "2.14.0"
    reloader         = "2.2.19"
  }

  # The default 4-minute LB idle timeout would cut live's websockets.
  traefik_service_annotations = merge(
    { "service.beta.kubernetes.io/azure-load-balancer-tcp-idle-timeout" = "30" },
    var.load_balancer_scheme == "internal" ? {
      "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
      "service.beta.kubernetes.io/azure-load-balancer-ipv4"     = var.internal_ingress_ip
      } : {
      "service.beta.kubernetes.io/azure-pip-name"                     = var.ingress_public_ip_name
      "service.beta.kubernetes.io/azure-load-balancer-resource-group" = var.resource_group_name
    },
  )
}

resource "terraform_data" "cluster_ready" {
  input = var.cluster_ready
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = local.external_secrets_namespace
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = local.chart_versions.external_secrets
  wait             = true

  values = [yamlencode({
    installCRDs = true
    # Keep CRDs: Plane's hook ExternalSecrets outlive the release, and deleting CRDs with the
    # controller leaves their finalizers stuck and the destroy times out.
    crds = { annotations = { "helm.sh/resource-policy" = "keep" } }
    # SecretStores use this controller identity (no serviceAccountRef).
    serviceAccount = {
      create = true
      name   = local.external_secrets_sa
      annotations = {
        "azure.workload.identity/client-id" = azurerm_user_assigned_identity.external_secrets.client_id
        "azure.workload.identity/tenant-id" = var.tenant_id
      }
    }
    podLabels = { "azure.workload.identity/use" = "true" }
  })]

  depends_on = [
    terraform_data.cluster_ready,
    azurerm_federated_identity_credential.external_secrets,
    azurerm_role_assignment.external_secrets_key_vault,
    azurerm_role_assignment.external_secrets_certificates,
  ]
}

resource "helm_release" "cert_manager" {
  count = local.cert_manager_enabled ? 1 : 0

  name             = "cert-manager"
  namespace        = local.cert_manager_namespace
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = local.chart_versions.cert_manager
  wait             = true

  values = [yamlencode({
    crds = { enabled = true }
    serviceAccount = {
      create = true
      name   = local.cert_manager_sa
    }
  })]

  depends_on = [terraform_data.cluster_ready]
}

resource "helm_release" "reloader" {
  name             = "reloader"
  namespace        = "reloader"
  create_namespace = true
  repository       = "https://stakater.github.io/stakater-charts"
  chart            = "reloader"
  version          = local.chart_versions.reloader
  wait             = true

  depends_on = [terraform_data.cluster_ready]
}

# externalTrafficPolicy: Local keeps the client IP (no proxy protocol needed).
resource "helm_release" "traefik" {
  count = var.install_traefik ? 1 : 0

  name             = "traefik"
  namespace        = "traefik"
  create_namespace = true
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = local.chart_versions.traefik
  wait             = true
  timeout          = 900

  values = [yamlencode({
    deployment = {
      replicas = 2
    }
    podDisruptionBudget = {
      enabled        = true
      maxUnavailable = 1
    }
    ingressClass = {
      enabled        = true
      isDefaultClass = false
      name           = "traefik"
    }
    providers = {
      kubernetesCRD     = { enabled = true }
      kubernetesIngress = { enabled = true }
    }
    ports = {
      web = {
        http = {
          redirections = {
            entryPoint = {
              to        = "websecure"
              scheme    = "https"
              permanent = true
            }
          }
        }
      }
      websecure = {
        # No read deadline: live's websockets and large uploads.
        transport = {
          respondingTimeouts = {
            readTimeout = 0
          }
        }
      }
    }
    service = {
      annotations = local.traefik_service_annotations
      spec = {
        type                     = "LoadBalancer"
        externalTrafficPolicy    = "Local"
        loadBalancerSourceRanges = var.allowed_cidrs
      }
    }
  })]

  depends_on = [terraform_data.cluster_ready]
}
