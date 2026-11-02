# Plane itself: one Helm release of plane-enterprise. The SecretStores, ExternalSecrets, the
# StorageClass of the in-cluster services and (path A) the certificates travel in the chart's own
# extraObjects, so there is no module-side chart and no kubernetes provider. Copied from the AWS
# module and adapted (no shared plane-k8s layer yet).

locals {
  # Release name and namespace feed MACHINE_SIGNATURE (the licence identity): never change them.
  release         = "plane"
  namespace       = "plane"
  service_account = "${local.release}-srv-account"
  cluster_domain  = "cluster.local"

  ##############################################################################
  # AZURE BLOB STORAGE: CHART CONTRACT (ASSUMED, NOT YET RELEASED)
  #
  # Plane's native Azure Blob support (api, silo and the plane-enterprise chart; plan B1-B3, B5) is
  # being built by Plane engineering. These are the planned chart values, proxy-only: uploads and
  # downloads go through Plane's API (use_storage_proxy), so the account needs no SAS and no CORS,
  # and Plane authenticates with its workload identity (no keys). When the real contract lands,
  # adjust this block only (tests/plane.tftest.hcl pins it, so it fails until updated too), and
  # bump plane_version / chart_version.
  ##############################################################################
  blob_env = {
    storage_provider      = "AZURE"
    azure_storage_account = var.data.storage_account_name
    azure_container       = var.data.storage_container_name
    # Optional in the contract (sovereign clouds, custom endpoints); the account's own endpoint.
    azure_blob_endpoint = var.data.storage_blob_endpoint
    use_storage_proxy   = true
    # The generic bucket name the chart always renders (AWS_S3_BUCKET_NAME); kept equal to the container.
    docstore_bucket = var.data.storage_container_name
  }
  blob_service_account = {
    annotations = { "azure.workload.identity/client-id" = azurerm_user_assigned_identity.plane.client_id }
    podLabels   = { "azure.workload.identity/use" = "true" }
  }
  # No bundled MinIO: Blob is the only object store.
  blob_minio = { local_setup = false }
  ##############################################################################

  # Path A, Let's Encrypt: cert-manager issues the web certificate (HTTP-01 through Traefik).
  issue_cert = var.ingress_enabled && var.acme_email != null

  hook = {
    store   = { "helm.sh/hook" = "pre-install,pre-upgrade", "helm.sh/hook-weight" = "-10", "helm.sh/hook-delete-policy" = "before-hook-creation" }
    secrets = { "helm.sh/hook" = "pre-install,pre-upgrade", "helm.sh/hook-weight" = "-5", "helm.sh/hook-delete-policy" = "before-hook-creation" }
  }

  # The module's Key Vault. No auth block: the External Secrets controller uses its own workload
  # identity (no serviceAccountRef).
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

  # Customer certificates (path A web; email in any path) from Key Vault, by versionless ID, synced
  # into kubernetes.io/tls Secrets before Plane's pods start. One SecretStore per vault; the Key Vault
  # DNS suffix comes from the module's own vault, so sovereign clouds work too.
  key_vault_dns_suffix = regex("^https://[^.]+\\.([^/]+)", var.data.key_vault_uri)[0]
  certificate_stores   = { for v in distinct([for c in values(var.certificates) : c.vault]) : v => "key-vault-${v}" }
  certificate_store_objects = [
    for vault, store in local.certificate_stores : {
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
  # A Key Vault certificate's backing secret holds the key and the chain: PEM as imported, or a
  # base64 PFX. The template handles both.
  customer_certificates = {
    for k, c in var.certificates : local.certificate_targets[k].name => {
      apiVersion = "external-secrets.io/v1"
      kind       = "ExternalSecret"
      metadata   = { name = local.certificate_targets[k].name, annotations = local.hook.secrets }
      spec = {
        refreshInterval = "1h"
        secretStoreRef  = { name = local.certificate_stores[c.vault], kind = "SecretStore" }
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

  # Every workload that reads a Secret gets the Reloader annotation, so a rotated credential
  # rolls the pods (Reloader reads it on the workload, which the chart sets from
  # services.<name>.annotations).
  reloaded_services = [
    "api", "worker", "beatworker", "worker_importers", "external_api", "outbox_poller",
    "automation_consumer", "webhook_consumer", "agent_consumer", "live", "live_exporter",
    "silo", "pi", "pi_worker", "pi_beat_worker", "mcp_server", "runner", "email_service", "argus",
  ]

  # Key Vault secrets mirrored as they are (JSON keys = the chart's external_secrets.* keys).
  external_secret = {
    for name, key in {
      "plane-db"       = var.data.postgres_secret_name
      "plane-redis"    = var.data.redis_secret_name
      "plane-rabbitmq" = var.data.rabbitmq_secret_name
      "plane-app-keys" = var.data.app_keys_secret_name
      } : name => {
      apiVersion = "external-secrets.io/v1"
      kind       = "ExternalSecret"
      metadata   = { name = name, annotations = local.hook.secrets }
      spec = {
        # Nothing here rotates on its own; Reloader rolls the pods when a value changes.
        refreshInterval = "1h"
        secretStoreRef  = { name = local.secret_store, kind = "SecretStore" }
        # Orphan: recreating the hook object on upgrade must not garbage-collect the live Secret.
        target   = { name = name, creationPolicy = "Orphan" }
        dataFrom = [{ extract = { key = key } }]
      }
    }
  }

  # The in-cluster OpenSearch reads its credentials from a whole Secret (opensearch_existingSecret) whose
  # keys mirror the chart's own <release>-opensearch-secrets; the module templates it from Key Vault.
  # The key list is chart-internal: re-check it on every chart bump.
  opensearch_secret = "${local.release}-opensearch-creds"
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
            OPENSEARCH_EMBEDDING_DIMENSION    = "1536"
          }
        }
      }
      dataFrom = [{ extract = { key = coalesce(var.data.opensearch_secret_name, "plane-opensearch") } }]
    }
  }

  # Zone-redundant disks for the in-cluster RabbitMQ and OpenSearch, so their pods can move to
  # another zone. Helm installs a StorageClass before the StatefulSets.
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
          # HTTP-01: cert-manager's challenge Ingress, served by Traefik on port 80. The module
          # touches no DNS, so no DNS-01.
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

  # Managed PostgreSQL and Redis; Blob instead of MinIO. Azure has no managed RabbitMQ (AMQP 0-9-1)
  # or OpenSearch, so both run in the cluster from the chart, with their credentials from Key Vault.
  data_services = {
    postgres = { local_setup = false }
    redis    = { local_setup = false }
    minio    = local.blob_minio
    # Bundled broker and the apps read one Secret (external_secrets.rabbitmq, chart 3.11.5+).
    rabbitmq   = { local_setup = true, volumeSize = "${var.rabbitmq.volume_size_gb}Gi" }
    opensearch = { local_setup = var.opensearch.enabled, volumeSize = "${var.opensearch.volume_size_gb}Gi" }
  }

  # Background services the paid features depend on, on as in today's managed deployment
  # (the chart defaults them off): Automations needs outbox_poller (it fills the event stream),
  # automation_consumer and the script runner; agent runs and event-stream webhooks need their
  # consumers; live's link previews call iframely; imports run on worker_importers (its queue is
  # wired below). external_api stays off: the chart points silo at the api.
  # Email service (chart 3.11.3+). On by default with its own load balancer on the module's static
  # public IP (email.load_balancer; without it, a ClusterIP Service). The chart renders
  # externalTrafficPolicy: Local, which keeps the sender's IP (SPF). Certificate: the customer's, from
  # Key Vault (email.certificate_secret_id); otherwise none, and the email app generates a self-signed
  # one at startup (fine for mail servers on port 25, which use opportunistic TLS).
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

  core_services = {
    for s in [
      "outbox_poller", "automation_consumer", "runner", "agent_consumer", "webhook_consumer",
      "iframely", "worker_importers",
    ] : s => { enabled = true }
  }

  # Two replicas for the user-facing and busiest workloads, spread across nodes, so a node drain or
  # node-image upgrade doesn't take Plane down. The PodDisruptionBudgets only apply to multi-replica
  # workloads.
  replica_services = {
    for s in ["api", "worker", "web", "live"] : s => {
      replicas                  = 2
      topologySpreadConstraints = [{ topologyKey = "kubernetes.io/hostname", maxSkew = 1, whenUnsatisfiable = "ScheduleAnyway" }]
    }
  }

  component_services = {
    email_service = local.email_service
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

    # Path A: Plane's Traefik routes. Path B: none; the customer applies their own routes.
    ingress = {
      enabled      = var.ingress_enabled
      controller   = "traefik"
      ingressClass = "traefik"
    }

    ssl = { tls_secret_name = var.tls_secret_name }

    serviceAccount = merge({ create = true }, local.blob_service_account)

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

      # In-cluster OpenSearch: endpoint and credentials come from opensearch_existingSecret.
      opensearch_index_prefix = var.opensearch.enabled ? var.opensearch.index_prefix : ""

      # silo publishes imports to worker_importers' queue (chart default: the main worker's).
      silo_envs = { importers_queue_name = "celery.importer" }

      email_service_envs = { smtp_domain = var.email.enabled && var.email.smtp_domain != null ? var.email.smtp_domain : "" }

      # Azure Managed Redis: TLS only, on port 10000.
      redis_host = var.data.redis_host
      redis_port = tostring(var.data.redis_port)
      redis_ssl  = true

      # In-cluster RabbitMQ: plain AMQP inside the cluster.
      rabbitmq_port  = "5672"
      rabbitmq_ssl   = false
      rabbitmq_vhost = "/"

      # As today's managed deployment: any attachment type can be uploaded.
      allow_all_attachment_types = true
    }, local.blob_env)

    external_secrets = {
      database                  = { secretName = "plane-db", usernameKey = "username", passwordKey = "password" }
      redis                     = { secretName = "plane-redis", passwordKey = "password" }
      rabbitmq                  = { secretName = "plane-rabbitmq", usernameKey = "username", passwordKey = "password" }
      app_keys_existingSecret   = "plane-app-keys"
      opensearch_existingSecret = var.opensearch.enabled ? local.opensearch_secret : ""
    }

    # The chart has no value for the api's TRUSTED_PROXIES yet (chart change C-8). With Azure CNI
    # Overlay the client connection reaches the api from Traefik's pod IP, so the pod CIDR is the
    # trusted proxy range (the Azure load balancer keeps the client IP: externalTrafficPolicy Local).
    extraEnv = [
      { name = "TRUSTED_PROXIES", value = var.pod_cidr },
      # Route import tasks to worker_importers' queue (the chart doesn't set this for the api).
      { name = "CELERY_IMPORTERS_QUEUE_ENABLED", value = "1" },
    ]

    extraObjects = concat(
      [local.storage_class_object, local.secret_store_object],
      local.certificate_store_objects,
      values(local.external_secret),
      var.opensearch.enabled ? [local.opensearch_external_secret] : [],
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
    azurerm_federated_identity_credential.plane,
    azurerm_role_assignment.plane_blob,
  ]
}
