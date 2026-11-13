# GKE already runs metrics-server, the PD CSI driver and the load balancer integration.

locals {
  external_secrets_namespace = "external-secrets"
  external_secrets_sa        = "external-secrets"
  cert_manager_namespace     = "cert-manager"
  cert_manager_sa            = "cert-manager"

  # HTTP-01 through Traefik: cert-manager needs no GCP access and touches no DNS.
  cert_manager_enabled = var.issue_certificate

  chart_versions = {
    traefik          = "42.4.0"
    cert_manager     = "v1.21.3"
    external_secrets = "2.14.0"
    reloader         = "2.2.19"
  }

  traefik_service_annotations = merge(
    { "networking.gke.io/load-balancer-ip-addresses" = var.web_address_name },
    var.load_balancer_scheme == "internal" ? { "networking.gke.io/load-balancer-type" = "Internal" } : {},
  )
}

# Every release waits for the node pool through this gate.
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
    # Keep the CRDs: Plane's ExternalSecret hooks outlive the release and their finalizer needs the controller,
    # so deleting the CRDs with it hangs the destroy.
    crds = { annotations = { "helm.sh/resource-policy" = "keep" } }
    serviceAccount = {
      create      = true
      name        = local.external_secrets_sa
      annotations = { "iam.gke.io/gcp-service-account" = google_service_account.external_secrets.email }
    }
  })]

  depends_on = [
    terraform_data.cluster_ready,
    google_service_account_iam_member.external_secrets_workload_identity,
    google_secret_manager_secret_iam_member.external_secrets,
    google_secret_manager_secret_iam_member.external_secrets_customer,
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

# Path A only. The passthrough load balancer only passes TCP; Traefik terminates TLS.
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
      # External: GKE honours the static-IP annotation only on a backend service-based load balancer, which this
      # class selects (immutable). Internal: the annotation needs GKE subsetting, enabled on the cluster.
      spec = merge({
        type                     = "LoadBalancer"
        externalTrafficPolicy    = "Local"
        loadBalancerSourceRanges = var.allowed_cidrs
      }, var.load_balancer_scheme == "internal" ? {} : { loadBalancerClass = "networking.gke.io/l4-regional-external" })
    }
  })]

  depends_on = [terraform_data.cluster_ready]
}
