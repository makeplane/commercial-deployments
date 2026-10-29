# Plane itself: one Helm release of plane-enterprise. Secrets, the DB bootstrap Job and (with
# acme_email) the certificate travel in the chart's own extraObjects, so there is no
# module-side chart and no kubernetes provider.

locals {
  # Release name and namespace feed MACHINE_SIGNATURE (the licence identity): never change them.
  release         = "plane"
  namespace       = "plane"
  service_account = "${local.release}-srv-account"

  secret_store = "aws-secrets-manager"
  issue_cert   = var.acme_email != null
  # DNS-01 through Route 53 when the module has the zone; otherwise HTTP-01 through Traefik.
  dns01 = var.route53_zone_id != null

  # Every workload that reads a Secret gets the Reloader annotation, so a rotated credential
  # rolls the pods (Reloader reads it on the workload, which the chart sets from
  # services.<name>.annotations).
  reloaded_services = [
    "api", "worker", "beatworker", "worker_importers", "external_api", "outbox_poller",
    "automation_consumer", "webhook_consumer", "agent_consumer", "live", "live_exporter",
    "silo", "pi", "pi_worker", "pi_beat_worker", "mcp_server", "runner", "email_service", "argus",
  ]

  hook = {
    store   = { "helm.sh/hook" = "pre-install,pre-upgrade", "helm.sh/hook-weight" = "-10", "helm.sh/hook-delete-policy" = "before-hook-creation" }
    secrets = { "helm.sh/hook" = "pre-install,pre-upgrade", "helm.sh/hook-weight" = "-5", "helm.sh/hook-delete-policy" = "before-hook-creation" }
    db_init = { "helm.sh/hook" = "pre-install,pre-upgrade", "helm.sh/hook-weight" = "0", "helm.sh/hook-delete-policy" = "before-hook-creation,hook-succeeded" }
  }

  external_secret = {
    for name, arn in {
      "plane-db"       = var.data.postgres_secret_arn
      "plane-redis"    = var.data.redis_secret_arn
      "plane-rabbitmq" = var.data.rabbitmq_secret_arn
      "plane-app-keys" = var.data.app_keys_secret_arn
      } : name => {
      apiVersion = "external-secrets.io/v1"
      kind       = "ExternalSecret"
      metadata   = { name = name, annotations = local.hook.secrets }
      spec = {
        refreshInterval = "1h"
        secretStoreRef  = { name = local.secret_store, kind = "SecretStore" }
        # Orphan: recreating the hook object on upgrade must not garbage-collect the live Secret.
        target   = { name = name, creationPolicy = "Orphan" }
        dataFrom = [{ extract = { key = arn } }]
      }
    }
  }

  secret_store_object = {
    apiVersion = "external-secrets.io/v1"
    kind       = "SecretStore"
    metadata   = { name = local.secret_store, annotations = local.hook.store }
    # No auth block: the External Secrets controller uses its own Pod Identity role.
    spec = { provider = { aws = { service = "SecretsManager", region = var.region } } }
  }

  # pi needs its own database; the chart doesn't create it yet (chart change C-1).
  db_init_job = {
    apiVersion = "batch/v1"
    kind       = "Job"
    metadata   = { name = "plane-pi-db-init", annotations = local.hook.db_init }
    spec = {
      backoffLimit = 10
      template = {
        spec = {
          restartPolicy = "OnFailure"
          containers = [{
            name    = "create-plane-pi"
            image   = "postgres:15-alpine"
            command = ["/bin/sh", "-c", "psql -tAc \"SELECT 1 FROM pg_database WHERE datname = 'plane_pi'\" | grep -q 1 || psql -c 'CREATE DATABASE plane_pi'"]
            env = [
              { name = "PGHOST", value = var.data.postgres_host },
              { name = "PGPORT", value = tostring(var.data.postgres_port) },
              { name = "PGDATABASE", value = var.data.postgres_db },
              { name = "PGSSLMODE", value = "require" },
              { name = "PGUSER", valueFrom = { secretKeyRef = { name = "plane-db", key = "username" } } },
              { name = "PGPASSWORD", valueFrom = { secretKeyRef = { name = "plane-db", key = "password" } } },
            ]
          }]
        }
      }
    }
  }

  # The chart's mail certificate (for email.smtp_domain) references a namespaced Issuer
  # "<release>-cert-issuer", which the chart only creates when it manages TLS itself. The module
  # creates it: Let's Encrypt DNS-01 with a Route 53 zone, otherwise self-signed (inbound mail on
  # port 25 uses opportunistic TLS, which doesn't verify the certificate).
  email_issuer_start = local.dns01 ? 0 : 1
  email_issuer_objects = slice([
    {
      apiVersion = "cert-manager.io/v1"
      kind       = "Issuer"
      metadata   = { name = "${local.release}-cert-issuer" }
      spec = {
        acme = {
          server              = var.acme_server
          email               = var.acme_email
          privateKeySecretRef = { name = "${local.release}-cert-issuer-key" }
          solvers             = [{ dns01 = { route53 = { region = var.region, hostedZoneID = var.route53_zone_id } } }]
        }
      }
    },
    {
      apiVersion = "cert-manager.io/v1"
      kind       = "Issuer"
      metadata   = { name = "${local.release}-cert-issuer" }
      spec       = { selfSigned = {} }
    },
  ], local.email_issuer_start, local.email_issuer_start + (var.email.enabled ? 1 : 0))

  # Issuer + certificate only when acme_email is set; slice keeps the tuple type stable.
  certificate_objects = slice([
    {
      apiVersion = "cert-manager.io/v1"
      kind       = "ClusterIssuer"
      metadata   = { name = "plane-letsencrypt" }
      spec = {
        acme = {
          server              = var.acme_server
          email               = var.acme_email
          privateKeySecretRef = { name = "plane-letsencrypt-account" }
          # DNS-01: ambient credentials (cert-manager's Pod Identity role, scoped to the zone).
          # HTTP-01: cert-manager's challenge Ingress, served by Traefik on port 80.
          solvers = slice([
            { dns01 = { route53 = { region = var.region, hostedZoneID = var.route53_zone_id } } },
            { http01 = { ingress = { ingressClassName = "traefik" } } },
          ], local.dns01 ? 0 : 1, local.dns01 ? 1 : 2)
        }
      }
    },
    {
      apiVersion = "cert-manager.io/v1"
      kind       = "Certificate"
      metadata   = { name = "plane-tls" }
      spec = {
        secretName = var.tls_secret_name
        dnsNames   = [var.domain]
        issuerRef  = { kind = "ClusterIssuer", name = "plane-letsencrypt" }
      }
    },
  ], 0, local.issue_cert ? 2 : 0)

  data_services = {
    postgres   = { local_setup = false }
    redis      = { local_setup = false }
    rabbitmq   = { local_setup = false }
    minio      = { local_setup = false }
    opensearch = { local_setup = false }
  }

  component_services = {
    email_service = { enabled = var.email.enabled }
    silo          = { enabled = var.enable_components.silo }
    pi            = { enabled = var.enable_components.pi }
    drawio        = { local_setup = var.enable_components.drawio }
  }

  reloader_services = {
    for s in local.reloaded_services : s => { annotations = { "reloader.stakater.com/auto" = "true" } }
  }

  values = {
    planeVersion = var.plane_version

    license = { licenseDomain = var.domain }

    ingress = {
      enabled      = true
      controller   = "traefik"
      ingressClass = "traefik"
    }

    ssl = { tls_secret_name = var.tls_secret_name }

    serviceAccount = { create = true }

    services = {
      for s in distinct(concat(keys(local.data_services), keys(local.component_services), keys(local.reloader_services))) :
      s => merge(
        lookup(local.data_services, s, {}),
        lookup(local.component_services, s, {}),
        lookup(local.reloader_services, s, {}),
      )
    }

    env = {
      # Fail the render rather than fall back to the chart's public example keys.
      requireExplicitSecrets = true

      pgdb_host     = var.data.postgres_host
      pgdb_port     = tostring(var.data.postgres_port)
      pgdb_name     = var.data.postgres_db
      pg_pi_db_name = "plane_pi"

      # Managed OpenSearch, keyless: with no username/password and a pod identity, the api signs
      # with SigV4 (region from aws_region). Empty = search indexing off.
      opensearch_remote_url = var.data.opensearch_enabled ? "https://${var.data.opensearch_endpoint}" : ""

      email_service_envs = { smtp_domain = var.email.enabled ? var.email.smtp_domain : "" }

      redis_host = var.data.redis_host
      redis_port = tostring(var.data.redis_port)
      redis_ssl  = true

      rabbitmq_host  = var.data.rabbitmq_host
      rabbitmq_port  = tostring(var.data.rabbitmq_port)
      rabbitmq_ssl   = true
      rabbitmq_vhost = "/"

      # No access keys: the SDKs fall through to the pod's identity.
      storage_provider      = "S3"
      docstore_bucket       = var.data.bucket_name
      aws_region            = var.region
      aws_access_key        = ""
      aws_secret_access_key = ""
      use_storage_proxy     = false
    }

    external_secrets = {
      database                = { secretName = "plane-db", usernameKey = "username", passwordKey = "password" }
      redis                   = { secretName = "plane-redis", passwordKey = "password" }
      rabbitmq                = { secretName = "plane-rabbitmq", usernameKey = "username", passwordKey = "password" }
      app_keys_existingSecret = "plane-app-keys"
    }

    # The chart has no value for the api's TRUSTED_PROXIES yet (chart change C-8). Traefik sits
    # behind the NLB inside the VPC, so the VPC CIDR is the trusted proxy range.
    extraEnv = [{ name = "TRUSTED_PROXIES", value = var.vpc_cidr }]

    extraObjects = concat(
      [local.secret_store_object],
      values(local.external_secret),
      [local.db_init_job],
      local.certificate_objects,
      local.email_issuer_objects,
    )
  }
}

resource "terraform_data" "addons_ready" {
  input = var.addons_ready
}

resource "helm_release" "plane" {
  name             = local.release
  namespace        = local.namespace
  create_namespace = true
  repository       = "https://helm.plane.so/"
  chart            = "plane-enterprise"
  version          = var.chart_version

  wait    = true
  timeout = var.helm_timeout
  # Keep failed pods around for debugging instead of rolling back.
  atomic = false

  values = compact([yamlencode(local.values), var.plane_values])

  depends_on = [terraform_data.addons_ready, module.plane_pod_identity, aws_opensearch_domain_policy.plane]
}

# The NLB the LB controller creates for the chart's email Service (looked up by its tags once the
# release, which waits for the LoadBalancer address, is installed).
data "aws_lb" "email" {
  count = var.email.enabled ? 1 : 0

  tags = {
    "elbv2.k8s.aws/cluster" = var.cluster_name
    "service.k8s.aws/stack" = "${local.namespace}/${local.release}-email-service"
  }

  depends_on = [helm_release.plane]
}
