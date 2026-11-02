# Traefik's load balancer (path A) and External Secrets. Runs the addons module alone with mock providers.

mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      email  = "plane-test-eso@plane-test-project.iam.gserviceaccount.com"
      member = "serviceAccount:plane-test-eso@plane-test-project.iam.gserviceaccount.com"
      name   = "projects/plane-test-project/serviceAccounts/plane-test-eso@plane-test-project.iam.gserviceaccount.com"
    }
  }
}
mock_provider "helm" {}

variables {
  name                 = "plane-test"
  project_id           = "plane-test-project"
  install_traefik      = true
  allowed_cidrs        = ["0.0.0.0/0"]
  load_balancer_scheme = "internet-facing"
  web_address_name     = "plane-test-web"
  issue_certificate    = false
  certificate_secrets  = []
  secret_ids = {
    app_keys = "projects/plane-test-project/secrets/plane-test-plane-app-keys"
    postgres = "projects/plane-test-project/secrets/plane-test-plane-db"
  }
  cluster_ready = "plane-test"
}

run "internet_facing_external_address" {
  command = plan
  module {
    source = "./modules/addons"
  }

  assert {
    condition     = yamldecode(helm_release.traefik[0].values[0]).service.annotations["networking.gke.io/load-balancer-ip-addresses"] == "plane-test-web"
    error_message = "Traefik's load balancer must use the reserved web address."
  }
  assert {
    condition     = !contains(keys(yamldecode(helm_release.traefik[0].values[0]).service.annotations), "networking.gke.io/load-balancer-type")
    error_message = "An internet-facing Traefik load balancer must not be internal."
  }
  assert {
    condition     = yamldecode(helm_release.traefik[0].values[0]).service.spec.externalTrafficPolicy == "Local"
    error_message = "Traefik's Service must keep the client IP (externalTrafficPolicy Local)."
  }
  assert {
    condition     = yamldecode(helm_release.traefik[0].values[0]).service.spec.loadBalancerSourceRanges == ["0.0.0.0/0"]
    error_message = "Traefik's Service must allow only ingress.allowed_cidrs."
  }
  assert {
    condition     = !can(yamldecode(helm_release.traefik[0].values[0]).ports.websecure.proxyProtocol)
    error_message = "No proxy protocol on GKE: the passthrough load balancer keeps the client IP."
  }
  assert {
    condition     = length(helm_release.cert_manager) == 0
    error_message = "cert-manager runs only with Let's Encrypt."
  }
}

run "internal_address" {
  command = plan
  module {
    source = "./modules/addons"
  }
  variables {
    load_balancer_scheme = "internal"
    allowed_cidrs        = ["10.0.0.0/8"]
  }

  assert {
    condition     = yamldecode(helm_release.traefik[0].values[0]).service.annotations["networking.gke.io/load-balancer-type"] == "Internal"
    error_message = "An internal Traefik load balancer must carry the GKE Internal annotation."
  }
  assert {
    condition     = yamldecode(helm_release.traefik[0].values[0]).service.spec.loadBalancerSourceRanges == ["10.0.0.0/8"]
    error_message = "Traefik's Service must allow only ingress.allowed_cidrs."
  }
}

run "path_b_no_traefik" {
  command = plan
  module {
    source = "./modules/addons"
  }
  variables {
    install_traefik  = false
    web_address_name = null
  }

  assert {
    condition     = length(helm_release.traefik) == 0
    error_message = "Path B must not install Traefik."
  }
}

run "external_secrets_identity" {
  module {
    source = "./modules/addons"
  }
  variables {
    issue_certificate   = true
    certificate_secrets = ["projects/plane-test-project/secrets/plane-mail-tls"]
  }

  assert {
    condition     = yamldecode(helm_release.external_secrets.values[0]).crds.annotations["helm.sh/resource-policy"] == "keep"
    error_message = "External Secrets' CRDs must survive the uninstall (Plane's hook ExternalSecrets need them on destroy)."
  }
  assert {
    condition     = yamldecode(helm_release.external_secrets.values[0]).serviceAccount.annotations["iam.gke.io/gcp-service-account"] == "plane-test-eso@plane-test-project.iam.gserviceaccount.com"
    error_message = "External Secrets' ServiceAccount must be bound to its Google service account (Workload Identity)."
  }
  assert {
    condition     = google_service_account_iam_member.external_secrets_workload_identity.member == "serviceAccount:plane-test-project.svc.id.goog[external-secrets/external-secrets]"
    error_message = "Only External Secrets' Kubernetes ServiceAccount may act as its Google service account."
  }
  assert {
    condition     = toset(keys(google_secret_manager_secret_iam_member.external_secrets)) == toset(["app_keys", "postgres"])
    error_message = "External Secrets must be allowed to read each module secret."
  }
  assert {
    condition     = toset(keys(google_secret_manager_secret_iam_member.external_secrets_certificates)) == toset(["plane-mail-tls"])
    error_message = "External Secrets must be allowed to read the customer's certificate secrets, by name."
  }
  assert {
    condition     = length(helm_release.cert_manager) == 1
    error_message = "cert-manager must run with Let's Encrypt."
  }
}
