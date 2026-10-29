# Every in-cluster add-on is a Helm release with a pinned chart version.

locals {
  lb_controller_sa           = "aws-load-balancer-controller"
  external_secrets_namespace = "external-secrets"
  external_secrets_sa        = "external-secrets"
  cert_manager_namespace     = "cert-manager"
  cert_manager_sa            = "cert-manager"

  # Fixed name, so Terraform can find the NLB the controller creates (edge module).
  load_balancer_name = "${var.name}-traefik"

  # cert-manager runs when the module issues the certificate. It only needs AWS access (Route 53)
  # for DNS-01; HTTP-01 goes through Traefik.
  cert_manager_enabled = var.issue_certificate
  cert_manager_dns01   = var.issue_certificate && var.route53_zone_id != null

  chart_versions = {
    # 1.17.x ships controller v2.17.x. Chart 3.x (controller v3) needs the Gateway API CRDs
    # installed with kubectl, which breaks the Helm-only rule.
    aws_load_balancer_controller = "1.17.1"
    traefik                      = "42.1.3"
    cert_manager                 = "v1.21.3"
    external_secrets             = "2.14.0"
    reloader                     = "2.2.19"
    metrics_server               = "3.14.0"
  }
}

# Every release waits for the node group through this gate.
resource "terraform_data" "cluster_ready" {
  input = var.cluster_ready
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = local.chart_versions.aws_load_balancer_controller
  wait       = true

  values = [yamlencode({
    clusterName = var.cluster_name
    region      = var.region
    vpcId       = var.vpc_id
    serviceAccount = {
      create = true
      name   = local.lb_controller_sa
    }
    # Only Services that ask for it (Traefik's) get an NLB from this controller.
    enableServiceMutatorWebhook = false
  })]

  depends_on = [terraform_data.cluster_ready, module.lb_controller_pod_identity]
}

# On destroy, Traefik's Service is deleted first and the LB controller removes the NLB
# asynchronously. Keep the controller around long enough for that.
resource "time_sleep" "nlb_cleanup" {
  destroy_duration = "120s"

  depends_on = [helm_release.aws_load_balancer_controller]
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
    serviceAccount = {
      create = true
      name   = local.external_secrets_sa
    }
  })]

  depends_on = [terraform_data.cluster_ready, module.external_secrets_pod_identity]
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

  depends_on = [terraform_data.cluster_ready, module.cert_manager_pod_identity]
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

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = local.chart_versions.metrics_server
  wait       = true

  depends_on = [terraform_data.cluster_ready]
}

# Traefik behind an internet-facing NLB with AWS-assigned IPs. The NLB only passes TCP;
# Traefik terminates TLS. Proxy protocol carries the real client IP through the NLB.
resource "helm_release" "traefik" {
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
        proxyProtocol = { trustedIPs = [var.vpc_cidr] }
      }
      websecure = {
        proxyProtocol = { trustedIPs = [var.vpc_cidr] }
        # Long-lived websockets (live) and large uploads: no read deadline on the entrypoint.
        transport = {
          respondingTimeouts = {
            readTimeout = 0
          }
        }
      }
    }
    service = {
      annotations = {
        "service.beta.kubernetes.io/aws-load-balancer-type"                                = "external"
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"                     = "ip"
        "service.beta.kubernetes.io/aws-load-balancer-name"                                = local.load_balancer_name
        "service.beta.kubernetes.io/aws-load-balancer-scheme"                              = "internet-facing"
        "service.beta.kubernetes.io/aws-load-balancer-subnets"                             = join(",", var.public_subnet_ids)
        "service.beta.kubernetes.io/aws-load-balancer-proxy-protocol"                      = "*"
        "service.beta.kubernetes.io/aws-load-balancer-target-group-attributes"             = "preserve_client_ip.enabled=false"
        "service.beta.kubernetes.io/aws-load-balancer-manage-backend-security-group-rules" = "true"
      }
      spec = {
        type                     = "LoadBalancer"
        loadBalancerSourceRanges = var.allowed_cidrs
      }
    }
  })]

  # The LB controller must be running to create the NLB, and still running (plus the cleanup
  # wait) when the Service is deleted on destroy, so it removes the NLB.
  depends_on = [helm_release.aws_load_balancer_controller, time_sleep.nlb_cleanup]
}
