# The two edge paths (A: ingress.mode = "automated", B: "none") and their input rules. Mock providers: no GCP
# credentials or cluster needed. Run: terraform init && terraform test

mock_provider "google" {
  mock_resource "google_compute_address" {
    defaults = { address = "203.0.113.10" }
  }
  mock_resource "google_service_account" {
    defaults = {
      email  = "plane-test-mock@plane-test-project.iam.gserviceaccount.com"
      member = "serviceAccount:plane-test-mock@plane-test-project.iam.gserviceaccount.com"
      name   = "projects/plane-test-project/serviceAccounts/plane-test-mock@plane-test-project.iam.gserviceaccount.com"
    }
  }
}
mock_provider "helm" {}
mock_provider "random" {}
mock_provider "time" {}

# The network, cluster and data layers are replaced by fixed outputs.
override_module {
  target = module.network
  outputs = {
    network_id                 = "projects/plane-test-project/global/networks/plane-test"
    network_name               = "plane-test"
    subnet_id                  = "projects/plane-test-project/regions/us-central1/subnetworks/plane-test"
    subnet_name                = "plane-test"
    pods_range_name            = "plane-test-pods"
    services_range_name        = "plane-test-services"
    private_service_range_name = "plane-test-psa"
    project_id                 = "plane-test-project"
  }
}

override_module {
  target = module.cluster
  outputs = {
    cluster_name                       = "plane-test"
    cluster_endpoint                   = "https://203.0.113.1"
    cluster_certificate_authority_data = "bW9jaw=="
    workload_pool                      = "plane-test-project.svc.id.goog"
    ready                              = "plane-test"
  }
}

override_module {
  target = module.data
  outputs = {
    postgres_instance_name = "plane-test-pg-abcd"
    postgres_host          = "10.60.32.3"
    redis_host             = "10.60.33.4"
    redis_port             = 6379
    bucket_name            = "plane-test-uploads-abcd1234"
    secret_ids = {
      postgres   = "projects/plane-test-project/secrets/plane-test-plane-db"
      redis      = "projects/plane-test-project/secrets/plane-test-plane-redis"
      rabbitmq   = "projects/plane-test-project/secrets/plane-test-plane-rabbitmq"
      opensearch = "projects/plane-test-project/secrets/plane-test-plane-opensearch"
      app_keys   = "projects/plane-test-project/secrets/plane-test-plane-app-keys"
    }
    plane_inputs = {
      bucket_name        = "plane-test-uploads-abcd1234"
      postgres_host      = "10.60.32.3"
      postgres_port      = 5432
      postgres_db        = "plane"
      redis_host         = "10.60.33.4"
      redis_port         = 6379
      redis_tls          = false
      redis_ca           = null
      opensearch_enabled = true
      secret_names = {
        postgres   = "plane-test-plane-db"
        redis      = "plane-test-plane-redis"
        rabbitmq   = "plane-test-plane-rabbitmq"
        opensearch = "plane-test-plane-opensearch"
        app_keys   = "plane-test-plane-app-keys"
      }
    }
  }
}

variables {
  name       = "plane-test"
  domain     = "plane.example.com"
  project_id = "plane-test-project"
  region     = "us-central1"
}

run "path_b_default" {
  assert {
    condition     = output.load_balancer_ip == null && output.dns_records.web == null
    error_message = "Path B must not have a Traefik load balancer or a web record."
  }
  assert {
    condition     = output.dns_records.email_mx != null && output.dns_records.email_host != null
    error_message = "The email load balancer (on by default) must give an A record for the mail host and an MX record."
  }
  assert {
    condition     = output.dns_records.email_host.value == output.email_load_balancer_ip && output.dns_records.email_host.name == "intake.plane.example.com"
    error_message = "The mail host A record must point intake.<domain> at the email load balancer's IP."
  }
  assert {
    condition     = output.dns_records.email_mx.value == "10 intake.plane.example.com"
    error_message = "The MX record must name the mail host (an MX can't point at an IP)."
  }
  assert {
    condition     = !yamldecode(output.plane_helm_values).ingress.enabled
    error_message = "Path B must not install Plane's routes."
  }
  assert {
    condition     = !contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.kind], "ClusterIssuer")
    error_message = "Path B must not issue certificates."
  }
  assert {
    condition     = module.edge.web_address_name == null
    error_message = "Path B must not reserve a web address."
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
    condition     = output.load_balancer_ip == "203.0.113.10" && output.dns_records.web.value == output.load_balancer_ip
    error_message = "Path A must expose Traefik's static IP and the web A record."
  }
  assert {
    condition     = startswith(output.dns_records.web.type, "A")
    error_message = "The web record must be an A record to the static IP."
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
    error_message = "A.1 must not read a web certificate from Secret Manager."
  }
}

run "a2_own_certificates" {
  variables {
    ingress = { mode = "automated", tls_certificate_secret = "projects/plane-test-project/secrets/plane-web-tls" }
    email   = { certificate_secret = "projects/plane-test-project/secrets/plane-mail-tls" }
  }

  assert {
    condition     = output.load_balancer_ip != null
    error_message = "Path A must expose Traefik's static IP."
  }
  assert {
    condition = alltrue([
      for n in ["plane-web-tls", "plane-mail-tls"] :
      contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.metadata.name], n)
    ])
    error_message = "A.2 must sync the web and email certificates from Secret Manager."
  }
  assert {
    condition = alltrue([
      for o in yamldecode(output.plane_helm_values).extraObjects :
      o.spec.dataFrom[0].extract.key == o.metadata.name if contains(["plane-web-tls", "plane-mail-tls"], o.metadata.name)
    ])
    error_message = "The certificate ExternalSecrets must read the secrets by their short name (the SecretStore is scoped to project_id)."
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

run "path_b_email_certificate" {
  variables {
    email = { certificate_secret = "projects/plane-test-project/secrets/plane-mail-tls" }
  }

  assert {
    condition     = contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.metadata.name], "plane-mail-tls")
    error_message = "The email certificate must be synced in path B too."
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
    ingress    = { mode = "automated", tls_certificate_secret = "projects/plane-test-project/secrets/plane-web-tls" }
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

run "reject_certificate_in_other_project" {
  command = plan
  variables {
    ingress = { mode = "automated", tls_certificate_secret = "projects/another-project/secrets/plane-web-tls" }
    email   = { certificate_secret = "plane-mail-tls" }
  }
  expect_failures = [var.ingress, var.email]
}

run "email_off" {
  variables {
    email = { enabled = false }
  }

  assert {
    condition     = output.dns_records.email_mx == null && output.dns_records.email_host == null && output.email_load_balancer_ip == null
    error_message = "email.enabled = false must turn off the email load balancer and its records too."
  }
}

run "email_without_load_balancer" {
  variables {
    email = { load_balancer = false }
  }

  assert {
    condition     = output.email_load_balancer_ip == null && yamldecode(output.plane_helm_values).services.email_service.service.type == "ClusterIP"
    error_message = "email.load_balancer = false must keep the service on a ClusterIP with no reserved address."
  }
}
