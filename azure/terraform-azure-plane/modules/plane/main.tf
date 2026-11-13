# In-cluster objects ride in the chart's extraObjects, so there's no kubernetes provider.

locals {
  # Release name and namespace feed MACHINE_SIGNATURE (the licence identity): never change them.
  release         = "plane"
  namespace       = "plane"
  service_account = "${local.release}-srv-account"
  cluster_domain  = "cluster.local"

  # AZURE BLOB STORAGE: the agreed chart contract, pending the chart and Plane releases (see README).
  # tests/plane.tftest.hcl pins it; update both together.
  blob_env = {
    storage_provider             = "AZURE"
    azure_storage_account_name   = var.data.storage_account_name
    azure_storage_container_name = var.data.storage_container_name
    azure_storage_blob_endpoint  = var.data.storage_blob_endpoint
    use_storage_proxy            = var.use_storage_proxy
  }
  blob_service_account = {
    annotations = { "azure.workload.identity/client-id" = azurerm_user_assigned_identity.plane.client_id }
    podLabels   = { "azure.workload.identity/use" = "true" }
  }
  blob_minio = { local_setup = false }

  issue_cert = var.ingress_enabled && var.acme_email != null

  hook = {
    store   = { "helm.sh/hook" = "pre-install,pre-upgrade", "helm.sh/hook-weight" = "-10", "helm.sh/hook-delete-policy" = "before-hook-creation" }
    secrets = { "helm.sh/hook" = "pre-install,pre-upgrade", "helm.sh/hook-weight" = "-5", "helm.sh/hook-delete-policy" = "before-hook-creation" }
  }

  # No auth block: the External Secrets controller uses its own workload identity.
  secret_store = "azure-key-vault"
  secret_store_object = {
    apiVersion = "external-secrets.io/v1"
    kind       = "SecretStore"
    metadata   = { name = local.secret_store, annotations = local.hook.store }
    spec = {
      provider = {
        azurekv = {
          authType = "WorkloadIdentity"
          vaultUrl = var.data.key_vault_uri
          tenantId = var.tenant_id
        }
      }
    }
  }

  # One SecretStore per customer vault; the DNS suffix comes from the module's vault (sovereign clouds).
  key_vault_dns_suffix = regex("^https://[^.]+\\.([^/]+)", var.data.key_vault_uri)[0]
  customer_stores = {
    for v in distinct(compact(concat([for c in values(var.certificates) : c.vault], [var.pi.api_keys_vault]))) : v => "key-vault-${v}"
  }
  customer_store_objects = [
    for vault, store in local.customer_stores : {
      apiVersion = "external-secrets.io/v1"
      kind       = "SecretStore"
      metadata   = { name = store, annotations = local.hook.store }
      spec = {
        provider = {
          azurekv = {
            authType = "WorkloadIdentity"
            vaultUrl = "https://${vault}.${local.key_vault_dns_suffix}/"
            tenantId = var.tenant_id
          }
        }
      }
    }
  ]

  email_tls_secret = "${local.release}-mail-tls-secret"
  certificate_targets = {
    web  = { name = "${local.release}-web-tls", secret = var.tls_secret_name }
    mail = { name = "${local.release}-mail-tls", secret = local.email_tls_secret }
  }
  # The certificate's backing secret is PEM as imported or a base64 PFX; the template handles both.
  customer_certificates = {
    for k, c in var.certificates : local.certificate_targets[k].name => {
      apiVersion = "external-secrets.io/v1"
      kind       = "ExternalSecret"
      metadata   = { name = local.certificate_targets[k].name, annotations = local.hook.secrets }
      spec = {
        refreshInterval = "1h"
        secretStoreRef  = { name = local.customer_stores[c.vault], kind = "SecretStore" }
        target = {
          name           = local.certificate_targets[k].secret
          creationPolicy = "Orphan"
          template = {
            type          = "kubernetes.io/tls"
            engineVersion = "v2"
            data = {
              "tls.crt" = "{{ if hasPrefix \"-----\" .certificate }}{{ .certificate | filterPEM \"CERTIFICATE\" }}{{ else }}{{ .certificate | b64dec | pkcs12cert }}{{ end }}"
              "tls.key" = "{{ if hasPrefix \"-----\" .certificate }}{{ .certificate | filterPEM \"PRIVATE KEY\" }}{{ else }}{{ .certificate | b64dec | pkcs12key }}{{ end }}"
            }
          }
        }
        data = [{ secretKey = "certificate", remoteRef = { key = "secret/${c.name}" } }]
      }
    }
  }

  # Reloader annotation on every workload that reads a Secret, so a rotated credential rolls the pods.
  reloaded_services = [
    "api", "worker", "beatworker", "worker_importers", "external_api", "outbox_poller",
    "automation_consumer", "webhook_consumer", "agent_consumer", "live", "live_exporter",
    "silo", "pi", "pi_worker", "pi_beat_worker", "mcp_server", "runner", "email_service", "argus",
  ]

  # Mirrored as is: the JSON keys are the chart's external_secrets.* keys.
  external_secret = {
    for name, key in {
      "plane-db"       = var.data.postgres_secret_name
      "plane-redis"    = var.data.redis_secret_name
      "plane-rabbitmq" = var.data.rabbitmq_secret_name
      } : name => {
      apiVersion = "external-secrets.io/v1"
      kind       = "ExternalSecret"
      metadata   = { name = name, annotations = local.hook.secrets }
      spec = {
        refreshInterval = "1h"
        secretStoreRef  = { name = local.secret_store, kind = "SecretStore" }
        # Orphan: recreating the hook object on upgrade must not garbage-collect the live Secret.
        target   = { name = name, creationPolicy = "Orphan" }
        dataFrom = [{ extract = { key = key } }]
      }
    }
  }

  # Each key mapped by name: a secret missing one fails to sync rather than Plane starting without it.
  app_keys_external_secret = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata   = { name = "plane-app-keys", annotations = local.hook.secrets }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = local.secret_store, kind = "SecretStore" }
      target          = { name = "plane-app-keys", creationPolicy = "Orphan" }
      data = [
        for k in var.data.app_key_names : { secretKey = k, remoteRef = { key = var.data.app_keys_secret_name, property = k } }
      ]
    }
  }

  # The customer's provider keys, each in the env var pi reads, from a plain-text secret or a JSON field; the root
  # module checks the IDs. pi puts the embedding key into the OpenSearch connector it creates.
  ai_providers_secret = "plane-ai-providers"
  pi_api_keys_object = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata   = { name = local.ai_providers_secret, annotations = local.hook.secrets }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = try(local.customer_stores[var.pi.api_keys_vault], ""), kind = "SecretStore" }
      target          = { name = local.ai_providers_secret, creationPolicy = "Orphan" }
      data = [for env, k in var.pi.api_key_secrets : {
        secretKey = env
        remoteRef = merge({ key = "secret/${k.name}" }, k.property == null ? {} : { property = k.property })
      }]
    }
  }

  # Keys mirror the chart-internal <release>-opensearch-secrets: re-check them on every chart bump.
  opensearch_secret = "${local.release}-opensearch"
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
            OPENSEARCH_URL                    = "http://${local.release}-opensearch.${local.namespace}.svc.${local.cluster_domain}:9200"
            OPENSEARCH_USERNAME               = "{{ .username }}"
            OPENSEARCH_PASSWORD               = "{{ .password }}"
            OPENSEARCH_INITIAL_ADMIN_PASSWORD = "{{ .password }}"
            OPENSEARCH_INDEX_PREFIX           = var.opensearch.index_prefix
            OPENSEARCH_EMBEDDING_DIMENSION    = tostring(var.pi.embedding_dimension)
          }
        }
      }
      dataFrom = [{ extract = { key = coalesce(var.data.opensearch_secret_name, "plane-opensearch") } }]
    }
  }

  # Zone-redundant disks, so the RabbitMQ and OpenSearch pods can move to another zone.
  storage_class_name = "plane-${lower(replace(var.persistent_volume_sku, "_", "-"))}"
  storage_class_object = {
    apiVersion           = "storage.k8s.io/v1"
    kind                 = "StorageClass"
    metadata             = { name = local.storage_class_name }
    provisioner          = "disk.csi.azure.com"
    parameters           = { skuName = var.persistent_volume_sku }
    reclaimPolicy        = "Delete"
    allowVolumeExpansion = true
    volumeBindingMode    = "WaitForFirstConsumer"
  }

  # Path A with Let's Encrypt only; slice keeps the tuple type stable.
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

  # Azure has no managed RabbitMQ (AMQP 0-9-1) or OpenSearch, so both run in the cluster.
  data_services = {
    postgres = { local_setup = false }
    redis    = { local_setup = false }
    minio    = local.blob_minio
    # The broker and the apps share one Secret (external_secrets.rabbitmq, chart 3.14.0+).
    rabbitmq = { local_setup = true, volumeSize = "${var.rabbitmq.volume_size_gb}Gi" }
    opensearch = merge(
      { local_setup = var.opensearch.enabled, volumeSize = "${var.opensearch.volume_size_gb}Gi" },
      # A chart default (a 768 MB heap) can't hold pi's vectors. Chart 3.14.0+.
      var.enable_components.pi ? { javaOpts = "-Xms1536m -Xmx1536m", memoryLimit = "3Gi" } : {},
    )
  }

  # Chart 3.11.3+. Without a certificate the email app self-signs (fine for port 25's opportunistic TLS).
  email_service = {
    enabled = var.email.enabled
    service = var.email.load_balancer ? {
      type = "LoadBalancer"
      annotations = {
        "service.beta.kubernetes.io/azure-pip-name"                     = var.email_public_ip_name
        "service.beta.kubernetes.io/azure-load-balancer-resource-group" = var.resource_group_name
      }
      } : {
      type        = "ClusterIP"
      annotations = {}
    }
    tls_secret_name = contains(keys(var.certificates), "mail") ? local.email_tls_secret : ""
    generateCert    = false
  }

  # Off in the chart, on as in today's managed deployment. external_api stays off: silo uses the api.
  core_services = {
    for s in [
      "outbox_poller", "automation_consumer", "runner", "agent_consumer", "webhook_consumer",
      "iframely", "worker_importers",
    ] : s => { enabled = true }
  }

  # Two replicas spread across nodes, so a node drain or image upgrade doesn't take Plane down.
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
        ai_providers = merge(
          { embedding_model = { enabled = true, name = var.pi.embedding_model, embedding_dimension = var.pi.embedding_dimension } },
          # pi's custom LLM; its key comes from the synced Secret (CUSTOM_LLM_API_KEY).
          var.pi.custom_llm == null ? {} : {
            custom_llm = {
              enabled    = true
              provider   = "openai"
              base_url   = var.pi.custom_llm.base_url
              model_key  = var.pi.custom_llm.model
              name       = var.pi.custom_llm.name
              max_tokens = var.pi.custom_llm.max_tokens
            }
          },
        )
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

    # Path A: Plane's Traefik routes. Path B: none; the customer applies their own routes.
    ingress = {
      enabled      = var.ingress_enabled
      controller   = "traefik"
      ingressClass = "traefik"
    }

    ssl = { tls_secret_name = var.tls_secret_name }

    serviceAccount = merge({ create = true, cloudIdentity = true }, local.blob_service_account)

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

    env = merge({
      # Fail the render rather than fall back to the chart's public example keys.
      requireExplicitSecrets = true

      # The in-cluster RabbitMQ and OpenSearch volumes.
      storageClass = local.storage_class_name

      pgdb_host     = var.data.postgres_host
      pgdb_port     = tostring(var.data.postgres_port)
      pgdb_name     = var.data.postgres_db
      pg_pi_db_name = "plane_pi"

      # Endpoint and credentials come from opensearch_existingSecret.
      opensearch_index_prefix = var.opensearch.enabled ? var.opensearch.index_prefix : ""

      # silo publishes imports to worker_importers' queue (chart default: the main worker's).
      silo_envs = { importers_queue_name = "celery.importer" }

      email_service_envs = { smtp_domain = var.email.enabled && var.email.smtp_domain != null ? var.email.smtp_domain : "" }

      # Azure Managed Redis is TLS only.
      redis_host = var.data.redis_host
      redis_port = tostring(var.data.redis_port)
      redis_ssl  = true

      rabbitmq_ssl   = false
      rabbitmq_vhost = "/"

      # As in today's managed deployment.
      allow_all_attachment_types = true
    }, local.blob_env)

    external_secrets = {
      database                    = { secretName = "plane-db", usernameKey = "username", passwordKey = "password" }
      redis                       = { secretName = "plane-redis", passwordKey = "password" }
      rabbitmq                    = { secretName = "plane-rabbitmq", usernameKey = "username", passwordKey = "password" }
      app_keys_existingSecret     = "plane-app-keys"
      opensearch_existingSecret   = var.opensearch.enabled ? local.opensearch_secret : ""
      ai_providers_existingSecret = var.enable_components.pi ? local.ai_providers_secret : ""
    }

    # No chart value for TRUSTED_PROXIES yet (C-8). With CNI Overlay, requests reach the api from
    # Traefik's pod IP, so the pod CIDR is the trusted proxy range.
    extraEnv = [
      { name = "TRUSTED_PROXIES", value = var.pod_cidr },
      # The chart doesn't set this for the api.
      { name = "CELERY_IMPORTERS_QUEUE_ENABLED", value = "1" },
    ]

    extraObjects = concat(
      [local.storage_class_object, local.secret_store_object],
      local.customer_store_objects,
      values(local.external_secret),
      [local.app_keys_external_secret],
      var.opensearch.enabled ? [local.opensearch_external_secret] : [],
      var.enable_components.pi ? [local.pi_api_keys_object] : [],
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
    time_sleep.plane_identity,
  ]
}
