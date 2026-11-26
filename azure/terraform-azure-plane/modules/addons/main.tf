# AKS ships metrics-server and LB integration, so unlike AWS neither is installed here.

locals {
  external_secrets_namespace = "external-secrets"
  external_secrets_sa        = "external-secrets"
  cert_manager_namespace     = "cert-manager"
  cert_manager_sa            = "cert-manager"
  traefik_namespace          = "traefik"

  # HTTP-01 through Traefik: cert-manager needs no Azure access and touches no DNS.
  cert_manager_enabled = var.issue_certificate

  chart_versions = {
    traefik          = "42.4.0"
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

  # The api prefers these client-settable headers to X-Forwarded-For, so any client could set the IP Plane
  # records. Traefik removes them (an empty value) on both entry points, which covers every chart route.
  client_ip_headers_middleware = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata   = { name = "strip-client-ip-headers", namespace = local.traefik_namespace }
    spec       = { headers = { customRequestHeaders = { "CF-Connecting-IP" = "", "True-Client-IP" = "" } } }
  }
  entrypoint_middlewares = ["${local.traefik_namespace}-${local.client_ip_headers_middleware.metadata.name}@kubernetescrd"]

  # Windows paths start C:/ or //server/: the kubelogin check uses where.exe there and sh elsewhere.
  windows = can(regex("^([A-Za-z]:|//)", abspath(path.root)))
}

# Without kubelogin the helm provider reads the releases as gone and plans them as new: stop the plan instead.
data "local_command" "kubelogin" {
  command                  = local.windows ? "where" : "sh"
  arguments                = local.windows ? ["/q", "kubelogin"] : ["-c", "command -v kubelogin >/dev/null"]
  allow_non_zero_exit_code = true

  lifecycle {
    postcondition {
      condition     = self.exit_code == 0
      error_message = "kubelogin isn't on PATH. Helm authenticates to AKS with kubelogin; without it the helm provider can't read the installed releases and the plan shows them as new. Install it (for example with `az aks install-cli`), make sure it's on PATH in the shell running Terraform (with the azurecli login, also run `az login`), and run the plan again."
    }
  }
}

# Every release waits for the cluster, and for the kubelogin check, through this gate.
resource "terraform_data" "cluster_ready" {
  input = var.cluster_ready

  depends_on = [data.local_command.kubelogin]
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
  namespace        = local.traefik_namespace
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
          middlewares = local.entrypoint_middlewares
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
        http = {
          middlewares = local.entrypoint_middlewares
        }
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
    extraObjects = [local.client_ip_headers_middleware]
  })]

  depends_on = [terraform_data.cluster_ready]
}
