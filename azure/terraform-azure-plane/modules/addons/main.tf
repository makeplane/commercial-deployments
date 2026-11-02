# Every in-cluster add-on is a Helm release with a pinned chart version. AKS ships metrics-server and
# its own cloud load balancer integration, so unlike AWS there is no LB controller or metrics-server.

locals {
  external_secrets_namespace = "external-secrets"
  external_secrets_sa        = "external-secrets"
  cert_manager_namespace     = "cert-manager"
  cert_manager_sa            = "cert-manager"

  # cert-manager runs only when the module issues the web certificate (path A, Let's Encrypt).
  # HTTP-01 through Traefik: it needs no Azure access and touches no DNS.
  cert_manager_enabled = var.issue_certificate

  chart_versions = {
    traefik          = "42.1.3"
    cert_manager     = "v1.21.3"
    external_secrets = "2.14.0"
    reloader         = "2.2.19"
  }

  # Traefik's Service: a static public IP from the module (internet-facing), or a fixed private IP
  # in the AKS subnet (internal). The Azure load balancer's default idle timeout (4 minutes) would cut
  # live's websockets, hence 30.
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

# Every release waits for the node pool and the deployer's cluster role through this gate.
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
    # Keep the CRDs on uninstall (as cert-manager does). Plane's ExternalSecrets are Helm hooks,
    # which Helm doesn't delete, and their cleanup finalizer needs the controller: deleting the
    # CRDs with the controller leaves them stuck and the destroy times out.
    crds = { annotations = { "helm.sh/resource-policy" = "keep" } }
    # Workload Identity: the webhook injects a token for this identity into the controller, and the
    # SecretStores use the controller's own identity (no serviceAccountRef).
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

# Path A only: Traefik behind an Azure Standard load balancer. The load balancer only passes TCP;
# Traefik terminates TLS. externalTrafficPolicy: Local keeps the client IP (no proxy protocol needed),
# and AKS writes loadBalancerSourceRanges into the nodes' network security group.
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
        # Long-lived websockets (live) and large uploads: no read deadline on the entrypoint.
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
