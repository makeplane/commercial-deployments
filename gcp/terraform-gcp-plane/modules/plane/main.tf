# Plane itself: one Helm release of plane-enterprise. Secrets and (path A) the certificates travel in the chart's own
# extraObjects, so there is no module-side chart and no kubernetes provider. RabbitMQ and OpenSearch run in the
# cluster from the chart (GCP has neither as a managed service).

locals {
  # Release name and namespace feed MACHINE_SIGNATURE (the licence identity): never change them.
  release         = "plane"
  namespace       = "plane"
  service_account = "${local.release}-srv-account"
  cluster_domain  = "cluster.local"

  rabbitmq_host   = "${local.release}-rabbitmq.${local.namespace}.svc.${local.cluster_domain}"
  opensearch_url  = "http://${local.release}-opensearch.${local.namespace}.svc.${local.cluster_domain}:9200"
  redis_ca_secret = "${local.release}-redis-ca"

  # The SecretStore reads Secret Manager in project_id. No auth block: the External Secrets controller uses its own
  # Workload Identity (addons module), as on AWS.
  secret_store = "gcp-secret-manager"
  secret_store_spec = {
    provider = { gcpsm = { projectID = var.project_id } }
  }

  # Path A, Let's Encrypt: cert-manager issues the web certificate (HTTP-01 through Traefik).
  issue_cert = var.ingress_enabled && var.acme_email != null

  # Customer certificates (path A web; email in any path) from Secret Manager: a secret whose value is JSON with the
  # keys "tls.crt" and "tls.key", synced into a kubernetes.io/tls Secret before Plane's pods start. The root module
  # checks the secret is in project_id, so the short name is the key.
  email_tls_secret = "${local.release}-mail-tls-secret"
  customer_certificates = {
    for name, c in {
      "${local.release}-web-tls"  = { secret = var.ingress_enabled ? var.tls_certificate_secret : null, target = var.tls_secret_name }
      "${local.release}-mail-tls" = { secret = var.email.enabled ? var.email.certificate_secret : null, target = local.email_tls_secret }
    } :
    name => {
      apiVersion = "external-secrets.io/v1"
      kind       = "ExternalSecret"
      metadata   = { name = name, annotations = local.hook.secrets }
      spec = {
        refreshInterval = "1h"
        secretStoreRef  = { name = local.secret_store, kind = "SecretStore" }
        target          = { name = c.target, creationPolicy = "Orphan", template = { type = "kubernetes.io/tls" } }
        dataFrom        = [{ extract = { key = regex("[^/]+$", c.secret) } }]
      }
    } if c.secret != null
  }

  # Every workload that reads a Secret gets the Reloader annotation, so a changed credential rolls the pods (Reloader
  # reads it on the workload, which the chart sets from services.<name>.annotations).
  reloaded_services = [
    "api", "worker", "beatworker", "worker_importers", "external_api", "outbox_poller",
    "automation_consumer", "webhook_consumer", "agent_consumer", "live", "live_exporter",
    "silo", "pi", "pi_worker", "pi_beat_worker", "mcp_server", "runner", "email_service", "argus",
  ]

  hook = {
    store   = { "helm.sh/hook" = "pre-install,pre-upgrade", "helm.sh/hook-weight" = "-10", "helm.sh/hook-delete-policy" = "before-hook-creation" }
    secrets = { "helm.sh/hook" = "pre-install,pre-upgrade", "helm.sh/hook-weight" = "-5", "helm.sh/hook-delete-policy" = "before-hook-creation" }
  }

  external_secret = {
    for name, key in {
      "plane-db"       = var.data.secret_names.postgres
      "plane-redis"    = var.data.secret_names.redis
      "plane-rabbitmq" = var.data.secret_names.rabbitmq
      "plane-app-keys" = var.data.secret_names.app_keys
      } : name => {
      apiVersion = "external-secrets.io/v1"
      kind       = "ExternalSecret"
      metadata   = { name = name, annotations = local.hook.secrets }
      spec = {
        # None of these rotate on their own (the Cloud SQL password is the module's): an hourly re-read picks up a
        # manual change, and Reloader then rolls the pods.
        refreshInterval = "1h"
        secretStoreRef  = { name = local.secret_store, kind = "SecretStore" }
        # Orphan: recreating the hook object on upgrade must not garbage-collect the live Secret.
        target   = { name = name, creationPolicy = "Orphan" }
        dataFrom = [{ extract = { key = key } }]
      }
    }
  }

  # The bundled OpenSearch reads everything from one Secret (external_secrets.opensearch_existingSecret): the chart
  # needs all seven OPENSEARCH_* keys, rendered here from the {username, password} secret.
  opensearch_secret = "plane-opensearch"
  opensearch_external_secret = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata   = { name = local.opensearch_secret, annotations = local.hook.secrets }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = local.secret_store, kind = "SecretStore" }
      target = {
        name           = local.opensearch_secret
        creationPolicy = "Orphan"
        template = {
          engineVersion = "v2"
          data = {
            OPENSEARCH_ENABLED                = "1"
            OPENSEARCH_URL                    = local.opensearch_url
            OPENSEARCH_USERNAME               = "{{ .username }}"
            OPENSEARCH_PASSWORD               = "{{ .password }}"
            OPENSEARCH_INITIAL_ADMIN_PASSWORD = "{{ .password }}"
            OPENSEARCH_INDEX_PREFIX           = var.opensearch.index_prefix
            OPENSEARCH_EMBEDDING_DIMENSION    = "1536"
          }
        }
      }
      dataFrom = [{ extract = { key = try(var.data.secret_names.opensearch, "") } }]
    }
  }

  secret_store_object = {
    apiVersion = "external-secrets.io/v1"
    kind       = "SecretStore"
    metadata   = { name = local.secret_store, annotations = local.hook.store }
    spec       = local.secret_store_spec
  }

  # Memorystore's server CA (a public certificate) for Plane's Node.js services (customCA), when Redis TLS is on.
  redis_ca_object = {
    apiVersion = "v1"
    kind       = "Secret"
    type       = "Opaque"
    metadata   = { name = local.redis_ca_secret, annotations = local.hook.secrets }
    stringData = { "ca.crt" = coalesce(var.data.redis_ca, "-") }
  }

  # Issuer + certificate only in path A with Let's Encrypt; slice keeps the tuple type stable.
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
          # HTTP-01: cert-manager's challenge Ingress, served by Traefik on port 80. The module touches no DNS, so no
          # DNS-01.
          solvers = [{ http01 = { ingress = { ingressClassName = "traefik" } } }]
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

  # GCP-specific: RabbitMQ and OpenSearch run in the cluster, on persistent disks of the GKE standard-rwo class.
  data_services = {
    postgres = { local_setup = false }
    redis    = { local_setup = false }
    minio    = { local_setup = false }
    rabbitmq = {
      local_setup = true
      volumeSize  = "${var.rabbitmq.volume_size_gb}Gi"
    }
    opensearch = merge(
      { local_setup = var.data.opensearch_enabled },
      var.data.opensearch_enabled ? { volumeSize = "${var.opensearch.volume_size_gb}Gi" } : {},
    )
  }

  # Background services the paid features depend on, on as in today's managed deployment (the chart defaults them
  # off): Automations needs outbox_poller (it fills the event stream), automation_consumer and the script runner;
  # agent runs and event-stream webhooks need their consumers; live's link previews call iframely; imports run on
  # worker_importers (its queue is wired below). external_api stays off: the chart points silo at the api.
  core_services = {
    for s in [
      "outbox_poller", "automation_consumer", "runner", "agent_consumer", "webhook_consumer",
      "iframely", "worker_importers",
    ] : s => { enabled = true }
  }

  # Email service. On by default with its own internet-facing passthrough load balancer on the reserved static IP
  # (email.load_balancer; without it, a ClusterIP Service, like today's managed deployment). The chart renders
  # externalTrafficPolicy: Local, which keeps the sender's IP (SPF). Certificate: the customer's, from Secret Manager
  # (email.certificate_secret); otherwise none, and the email app generates a self-signed one at startup (fine for mail
  # servers on port 25, which use opportunistic TLS).
  email_service = {
    enabled = var.email.enabled
    service = var.email.load_balancer ? {
      type        = "LoadBalancer"
      annotations = { "networking.gke.io/load-balancer-ip-addresses" = var.email_address_name }
      } : {
      type        = "ClusterIP"
      annotations = {}
    }
    tls_secret_name = var.email.certificate_secret != null ? local.email_tls_secret : ""
    generateCert    = false
  }

  # Two replicas for the user-facing and busiest workloads, spread across nodes, so a node drain or upgrade doesn't
  # take Plane down. The PodDisruptionBudgets (below) only apply to multi-replica workloads.
  replica_services = {
    for s in ["api", "worker", "web", "live"] : s => {
      replicas                  = 2
      topologySpreadConstraints = [{ topologyKey = "kubernetes.io/hostname", maxSkew = 1, whenUnsatisfiable = "ScheduleAnyway" }]
    }
  }

  component_services = {
    email_service = local.email_service
    silo          = { enabled = var.enable_components.silo }
    # Plane AI needs S3 (no GCS support yet): the root module refuses pi = true.
    pi     = { enabled = false }
    drawio = { local_setup = var.enable_components.drawio }
  }

  reloader_services = {
    for s in local.reloaded_services : s => { annotations = { "reloader.stakater.com/auto" = "true" } }
  }

  values = {
    planeVersion = var.plane_version

    license = { licenseDomain = var.domain }

    # Path A: Plane's Traefik routes. Path B: none; the customer applies their own routes.
    ingress = {
      enabled      = var.ingress_enabled
      controller   = "traefik"
      ingressClass = "traefik"
    }

    ssl = { tls_secret_name = var.tls_secret_name }

    # GKE Workload Identity: Plane's pods act as the module's Plane service account (bucket access only).
    serviceAccount = {
      create        = true
      cloudIdentity = true
      annotations   = { "iam.gke.io/gcp-service-account" = google_service_account.plane.email }
    }

    podDisruptionBudget = { enabled = true }

    services = {
      for s in distinct(concat(
        keys(local.data_services), keys(local.core_services), keys(local.replica_services),
        keys(local.component_services), keys(local.reloader_services),
      )) :
      s => merge(
        lookup(local.data_services, s, {}),
        lookup(local.core_services, s, {}),
        lookup(local.replica_services, s, {}),
        lookup(local.component_services, s, {}),
        lookup(local.reloader_services, s, {}),
      )
    }

    env = {
      # Fail the render rather than fall back to the chart's public example keys.
      requireExplicitSecrets = true

      # GKE's default PD CSI class. Required: with it unset the chart's OpenSearch volume asks for storageClassName ""
      # and never binds.
      storageClass = "standard-rwo"

      pgdb_host     = var.data.postgres_host
      pgdb_port     = tostring(var.data.postgres_port)
      pgdb_name     = var.data.postgres_db
      pg_pi_db_name = "plane_pi"

      opensearch_index_prefix = var.data.opensearch_enabled ? var.opensearch.index_prefix : ""

      # silo publishes imports to worker_importers' queue (chart default: the main worker's).
      silo_envs = { importers_queue_name = "celery.importer" }

      email_service_envs = { smtp_domain = var.email.enabled && var.email.smtp_domain != null ? var.email.smtp_domain : "" }

      redis_host = var.data.redis_host
      redis_port = tostring(var.data.redis_port)
      redis_ssl  = var.data.redis_tls

      # In-cluster RabbitMQ: plaintext AMQP inside the cluster.
      rabbitmq_ssl   = false
      rabbitmq_vhost = "/"

      # GCS through Application Default Credentials (Workload Identity): no key anywhere. Signed URLs are signed with
      # the IAM signBlob API as the Plane service account.
      storage_provider  = "GCS"
      docstore_bucket   = var.data.bucket_name
      gcs_bucket_name   = var.data.bucket_name
      gcs_project_id    = var.project_id
      use_storage_proxy = var.use_storage_proxy

      # As today's managed deployment: any attachment type can be uploaded.
      allow_all_attachment_types = true
    }

    external_secrets = merge(
      {
        database = { secretName = "plane-db", usernameKey = "username", passwordKey = "password" }
        redis    = { secretName = "plane-redis", passwordKey = "password" }
        # With services.rabbitmq.local_setup, the bundled broker and the apps both read this Secret (chart 3.11.5+).
        rabbitmq                = { secretName = "plane-rabbitmq", usernameKey = "username", passwordKey = "password" }
        app_keys_existingSecret = "plane-app-keys"
      },
      var.data.opensearch_enabled ? { opensearch_existingSecret = local.opensearch_secret } : {},
    )

    # Memorystore's server CA for the Node.js services (live, silo) when Redis TLS is on.
    customCA = { s3Secrets = var.data.redis_tls ? [{ name = local.redis_ca_secret, key = "ca.crt" }] : [] }

    # The chart has no value for the api's TRUSTED_PROXIES yet (chart change C-8). With externalTrafficPolicy Local
    # the load balancer hands the client IP straight to Traefik, which reaches the api from a pod IP.
    extraEnv = [
      { name = "TRUSTED_PROXIES", value = var.pods_cidr },
      # Route import tasks to worker_importers' queue (the chart doesn't set this for the api).
      { name = "CELERY_IMPORTERS_QUEUE_ENABLED", value = "1" },
    ]

    extraObjects = concat(
      [local.secret_store_object],
      values(local.external_secret),
      var.data.opensearch_enabled ? [local.opensearch_external_secret] : [],
      var.data.redis_tls ? [local.redis_ca_object] : [],
      local.certificate_objects,
      values(local.customer_certificates),
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
  repository       = var.chart_repository
  chart            = var.chart_name
  version          = var.chart_version

  wait    = true
  timeout = var.helm_timeout
  # Keep failed pods around for debugging instead of rolling back.
  atomic = false

  values = compact([yamlencode(local.values), var.plane_values])

  depends_on = [
    terraform_data.addons_ready,
    google_service_account_iam_member.plane_workload_identity,
    google_service_account_iam_member.plane_token_creator,
    google_storage_bucket_iam_member.plane,
  ]
}
