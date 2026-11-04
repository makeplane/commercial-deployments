# Secrets and certificates travel in the chart's extraObjects, so there is no kubernetes provider.

locals {
  # Release name and namespace feed MACHINE_SIGNATURE (the licence identity): never change them.
  release         = "plane"
  namespace       = "plane"
  service_account = "${local.release}-srv-account"
  cluster_domain  = "cluster.local"

  rabbitmq_host   = "${local.release}-rabbitmq.${local.namespace}.svc.${local.cluster_domain}"
  opensearch_url  = "http://${local.release}-opensearch.${local.namespace}.svc.${local.cluster_domain}:9200"
  redis_ca_secret = "${local.release}-redis-ca"

  # No auth block: the External Secrets controller uses its own Workload Identity.
  secret_store = "gcp-secret-manager"
  secret_store_spec = {
    provider = { gcpsm = { projectID = var.project_id } }
  }

  issue_cert = var.ingress_enabled && var.acme_email != null

  # Customer certificates: Secret Manager JSON with "tls.crt" and "tls.key". The root module checks the project.
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

  # Reloader rolls these workloads when a Secret they read changes.
  reloaded_services = [
    "api", "worker", "beatworker", "worker_importers", "external_api", "outbox_poller",
    "automation_consumer", "webhook_consumer", "agent_consumer", "live", "live_exporter",
    "silo", "pi", "pi_worker", "pi_beat_worker", "mcp_server", "runner", "email_service", "argus",
  ]

  hook = {
    store   = { "helm.sh/hook" = "pre-install,pre-upgrade", "helm.sh/hook-weight" = "-10", "helm.sh/hook-delete-policy" = "before-hook-creation" }
    secrets = { "helm.sh/hook" = "pre-install,pre-upgrade", "helm.sh/hook-weight" = "-5", "helm.sh/hook-delete-policy" = "before-hook-creation" }
  }

  # The customer's AI provider keys (JSON), read by the pi workloads and live. The root module checks the project.
  ai_providers_secret = "plane-ai-providers"
  pi_secrets          = var.enable_components.pi ? { (local.ai_providers_secret) = regex("[^/]+$", var.plane_ai.providers_secret) } : {}

  # Every plane_ai.embedding_model has 1536 dimensions; Plane's page search index uses the same.
  embedding_dimension = 1536

  external_secret = {
    for name, key in merge({
      "plane-db"       = var.data.secret_names.postgres
      "plane-redis"    = var.data.secret_names.redis
      "plane-rabbitmq" = var.data.secret_names.rabbitmq
      "plane-app-keys" = var.data.secret_names.app_keys
      }, local.pi_secrets) : name => {
      apiVersion = "external-secrets.io/v1"
      kind       = "ExternalSecret"
      metadata   = { name = name, annotations = local.hook.secrets }
      spec = {
        # Nothing rotates on its own; an hourly re-read picks up manual changes.
        refreshInterval = "1h"
        secretStoreRef  = { name = local.secret_store, kind = "SecretStore" }
        # Orphan: recreating the hook object on upgrade must not garbage-collect the live Secret.
        target   = { name = name, creationPolicy = "Orphan" }
        dataFrom = [{ extract = { key = key } }]
      }
    }
  }

  # The chart needs all seven OPENSEARCH_* keys in one Secret.
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
            OPENSEARCH_EMBEDDING_DIMENSION    = tostring(local.embedding_dimension)
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

  redis_ca_object = {
    apiVersion = "v1"
    kind       = "Secret"
    type       = "Opaque"
    metadata   = { name = local.redis_ca_secret, annotations = local.hook.secrets }
    stringData = { "ca.crt" = coalesce(var.data.redis_ca, "-") }
  }

  # slice, not a conditional, keeps the tuple type stable.
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
          # HTTP-01 through Traefik: the module touches no DNS.
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
      # Plane AI's k-NN and ML Commons need a bigger heap than the chart's 768 MB (javaOpts: chart 3.11.6+).
      var.enable_components.pi ? { javaOpts = "-Xms1536m -Xmx1536m", memoryLimit = "3Gi" } : {},
    )
  }

  # Paid features need these; the chart defaults them off. external_api stays off: silo uses the api.
  core_services = {
    for s in [
      "outbox_poller", "automation_consumer", "runner", "agent_consumer", "webhook_consumer",
      "iframely", "worker_importers",
    ] : s => { enabled = true }
  }

  # The chart sets externalTrafficPolicy Local (sender IP kept for SPF). No certificate: the email app self-signs.
  email_service = {
    enabled = var.email.enabled
    service = var.email.load_balancer ? {
      type        = "LoadBalancer"
      annotations = { "networking.gke.io/load-balancer-ip-addresses" = var.email_address_name }
      # Backend service-based load balancer: GKE honours the static-IP annotation only with this class (immutable).
      loadBalancerClass = "networking.gke.io/l4-regional-external"
      } : {
      type              = "ClusterIP"
      annotations       = {}
      loadBalancerClass = ""
    }
    tls_secret_name = var.email.certificate_secret != null ? local.email_tls_secret : ""
    generateCert    = false
  }

  # Two replicas across nodes, so a drain or upgrade doesn't take Plane down (PDBs need more than one).
  replica_services = {
    for s in ["api", "worker", "web", "live"] : s => {
      replicas                  = 2
      topologySpreadConstraints = [{ topologyKey = "kubernetes.io/hostname", maxSkew = 1, whenUnsatisfiable = "ScheduleAnyway" }]
    }
  }

  component_services = {
    email_service = local.email_service
    silo          = { enabled = var.enable_components.silo }
    pi = merge(
      { enabled = var.enable_components.pi },
      var.enable_components.pi ? {
        ai_providers = {
          embedding_model = { enabled = true, name = var.plane_ai.embedding_model, embedding_dimension = local.embedding_dimension }
        }
      } : {},
    )
    drawio = { local_setup = var.enable_components.drawio }
  }

  reloader_services = {
    for s in local.reloaded_services : s => { annotations = { "reloader.stakater.com/auto" = "true" } }
  }

  values = {
    planeVersion = var.plane_version

    license = { licenseDomain = var.domain }

    ingress = {
      enabled      = var.ingress_enabled
      controller   = "traefik"
      ingressClass = "traefik"
    }

    ssl = { tls_secret_name = var.tls_secret_name }

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

      # Required: unset, the chart's OpenSearch volume asks for storageClassName "" and never binds.
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

      rabbitmq_ssl   = false
      rabbitmq_vhost = "/"

      storage_provider  = "GCS"
      docstore_bucket   = var.data.bucket_name
      gcs_bucket_name   = var.data.bucket_name
      gcs_project_id    = var.project_id
      use_storage_proxy = var.use_storage_proxy

      allow_all_attachment_types = true
    }

    external_secrets = merge(
      {
        database = { secretName = "plane-db", usernameKey = "username", passwordKey = "password" }
        redis    = { secretName = "plane-redis", passwordKey = "password" }
        # With services.rabbitmq.local_setup, the bundled broker and the apps both read this Secret (chart 3.11.6+).
        rabbitmq                = { secretName = "plane-rabbitmq", usernameKey = "username", passwordKey = "password" }
        app_keys_existingSecret = "plane-app-keys"
      },
      var.data.opensearch_enabled ? { opensearch_existingSecret = local.opensearch_secret } : {},
      var.enable_components.pi ? { ai_providers_existingSecret = local.ai_providers_secret } : {},
    )

    # Memorystore's server CA for the Node.js services (live, silo).
    customCA = { s3Secrets = var.data.redis_tls ? [{ name = local.redis_ca_secret, key = "ca.crt" }] : [] }

    # No chart value for TRUSTED_PROXIES yet (chart change C-8); Traefik reaches the api from a pod IP.
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
