# Plane itself: one Helm release of plane-enterprise. Secrets, the DB bootstrap Job and (path A)
# the certificates travel in the chart's own extraObjects, so there is no module-side chart and
# no kubernetes provider.

locals {
  # Release name and namespace feed MACHINE_SIGNATURE (the licence identity): never change them.
  release         = "plane"
  namespace       = "plane"
  service_account = "${local.release}-srv-account"

  secret_store = "aws-secrets-manager"
  # Path A, Let's Encrypt: cert-manager issues the web certificate (HTTP-01 through Traefik).
  issue_cert = var.ingress_enabled && var.acme_email != null

  # Customer certificates (path A web; email in any path) from Secrets Manager: a secret with JSON
  # keys "tls.crt" and "tls.key", synced into a kubernetes.io/tls Secret before Plane's pods start.
  email_tls_secret = "${local.release}-mail-tls-secret"
  customer_certificates = {
    for name, c in {
      "${local.release}-web-tls"  = { arn = var.ingress_enabled ? var.tls_certificate_secret_arn : null, secret = var.tls_secret_name }
      "${local.release}-mail-tls" = { arn = var.email.enabled ? var.email.certificate_secret_arn : null, secret = local.email_tls_secret }
    } :
    name => {
      apiVersion = "external-secrets.io/v1"
      kind       = "ExternalSecret"
      metadata   = { name = name, annotations = local.hook.secrets }
      spec = {
        refreshInterval = "1h"
        secretStoreRef  = { name = local.secret_store, kind = "SecretStore" }
        target          = { name = c.secret, creationPolicy = "Orphan", template = { type = "kubernetes.io/tls" } }
        dataFrom        = [{ extract = { key = c.arn } }]
      }
    } if c.arn != null
  }

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
      } : name => {
      apiVersion = "external-secrets.io/v1"
      kind       = "ExternalSecret"
      metadata   = { name = name, annotations = local.hook.secrets }
      spec = {
        # RDS rotates its managed master password every 7 days and the old one stops working at
        # once: re-read it every minute (Reloader then rolls the pods). The others don't rotate.
        refreshInterval = name == "plane-db" ? "1m" : "1h"
        secretStoreRef  = { name = local.secret_store, kind = "SecretStore" }
        # Orphan: recreating the hook object on upgrade must not garbage-collect the live Secret.
        target   = { name = name, creationPolicy = "Orphan" }
        dataFrom = [{ extract = { key = arn } }]
      }
    }
  }

  # Generated, or an existing installation's (app_keys_secret_arn). Each key is mapped by name, so a
  # secret missing one fails to sync rather than Plane starting without it.
  app_keys_external_secret = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata   = { name = "plane-app-keys", annotations = local.hook.secrets }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = local.secret_store, kind = "SecretStore" }
      target          = { name = "plane-app-keys", creationPolicy = "Orphan" }
      data = [
        for k in var.data.app_key_names : { secretKey = k, remoteRef = { key = var.data.app_keys_secret_arn, property = k } }
      ]
    }
  }

  secret_store_object = {
    apiVersion = "external-secrets.io/v1"
    kind       = "SecretStore"
    metadata   = { name = local.secret_store, annotations = local.hook.store }
    # No auth block: the External Secrets controller uses its own Pod Identity role.
    spec = { provider = { aws = { service = "SecretsManager", region = var.region } } }
  }

  # Plane AI: an embedding model (pi creates it in OpenSearch at startup) and a chat model, either on
  # Amazon Bedrock through inference profiles (keyless) or with provider API keys from Secrets Manager.
  pi_bedrock   = var.pi.mode == "bedrock"
  pi_api_keys  = var.pi.mode == "api_keys"
  pi_ai_secret = "${local.release}-ai-providers"

  pi_ai_providers = merge(
    { for k, v in {
      embedding_model = {
        enabled             = true
        name                = var.pi.embedding_model
        embedding_dimension = var.pi.embedding_dimension
        aws_region          = var.region
      }
    } : k => v if var.pi.mode != null },
    # pi's custom LLM on Bedrock: with a profile and a pod identity it calls the profile keylessly.
    { for k, v in {
      custom_llm = {
        enabled    = true
        provider   = "bedrock"
        model_key  = try(var.pi.bedrock.chat_model_id, null)
        name       = try(var.pi.bedrock.chat_model_name, null)
        max_tokens = try(var.pi.bedrock.chat_max_tokens, null)
        aws_region = var.region
      }
      bedrock = {
        enabled               = true
        inference_profile_arn = try(aws_bedrock_inference_profile.pi["chat"].arn, null)
        region                = var.region
      }
    } : k => v if local.pi_bedrock },
    # pi's custom LLM on an OpenAI-compatible API (key: CUSTOM_LLM_API_KEY). A vendor key needs no
    # values: the synced Secret reaches pi through envFrom and pi offers that vendor's models.
    { for k, v in {
      custom_llm = {
        enabled    = true
        provider   = "openai"
        base_url   = try(var.pi.chat.base_url, null)
        model_key  = try(var.pi.chat.model, null)
        name       = try(var.pi.chat.name, null)
        max_tokens = try(var.pi.chat.max_tokens, null)
      }
    } : k => v if local.pi_api_keys && var.pi.chat != null },
  )

  # Each key in the env var pi reads (the chat key's, COHERE_API_KEY), from a plain-text secret or a JSON field.
  # pi puts the embedding key into the OpenSearch connector it creates.
  pi_api_keys_object = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata   = { name = local.pi_ai_secret, annotations = local.hook.secrets }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = local.secret_store, kind = "SecretStore" }
      target          = { name = local.pi_ai_secret, creationPolicy = "Orphan" }
      data = [for env, s in var.pi.api_key_secrets : {
        secretKey = env
        remoteRef = merge({ key = s.arn }, s.property == null ? {} : { property = s.property })
      }]
    }
  }

  # The chart has no values for these: identifiers, not secrets, so they go in extraEnv.
  pi_bedrock_env = local.pi_bedrock ? [
    { name = "BEDROCK_EMBEDDING_INFERENCE_PROFILE_ARN", value = try(aws_bedrock_inference_profile.pi["embeddings"].arn, null) },
    { name = "AWS_OPENSEARCH_CONNECTOR_ROLE_ARN", value = one(aws_iam_role.pi_connector[*].arn) },
  ] : []

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

  data_services = {
    postgres   = { local_setup = false }
    redis      = { local_setup = false }
    rabbitmq   = { local_setup = false }
    minio      = { local_setup = false }
    opensearch = { local_setup = false }
  }

  # Background services the paid features depend on, on as in today's managed deployment
  # (the chart defaults them off): Automations needs outbox_poller (it fills the event stream),
  # automation_consumer and the script runner; agent runs and event-stream webhooks need their
  # consumers; live's link previews call iframely; imports run on worker_importers (its queue is
  # wired below). external_api stays off: the chart points silo at the api.
  # Email service (chart 3.11.3+). On by default with its own internet-facing NLB
  # (email.load_balancer; without it, a ClusterIP Service, like today's managed deployment). On
  # the NLB, instance targets plus the Service's externalTrafficPolicy: Local keep the
  # sender's IP (SPF). Certificate: the customer's, from Secrets Manager (email.certificate_secret_arn);
  # otherwise none, and the email app generates a self-signed one at startup (fine for mail servers
  # on port 25, which use opportunistic TLS).
  email_load_balancer_name = "${var.name}-email"
  email_service = {
    enabled = var.email.enabled
    service = var.email.load_balancer ? {
      type = "LoadBalancer"
      annotations = {
        "service.beta.kubernetes.io/aws-load-balancer-type"                                = "external"
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"                     = "instance"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"                              = "internet-facing"
        "service.beta.kubernetes.io/aws-load-balancer-name"                                = local.email_load_balancer_name
        "service.beta.kubernetes.io/aws-load-balancer-subnets"                             = join(",", var.public_subnet_ids)
        "service.beta.kubernetes.io/aws-load-balancer-manage-backend-security-group-rules" = "true"
      }
      } : {
      type        = "ClusterIP"
      annotations = {}
    }
    tls_secret_name = var.email.certificate_secret_arn != null ? local.email_tls_secret : ""
    generateCert    = false
  }

  core_services = {
    for s in [
      "outbox_poller", "automation_consumer", "runner", "agent_consumer", "webhook_consumer",
      "iframely", "worker_importers",
    ] : s => { enabled = true }
  }

  # Two replicas for the user-facing and busiest workloads, spread across nodes, so a node drain or
  # node-group update doesn't take Plane down. The PodDisruptionBudgets (below) only apply to
  # multi-replica workloads.
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
      { for k, v in { ai_providers = local.pi_ai_providers } : k => v if length(local.pi_ai_providers) > 0 },
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

    # Bound to Plane's role by an EKS Pod Identity association (outside the chart). Renders nothing;
    # it lets helm upgrade warn about settings that conflict with an attached identity.
    serviceAccount = { create = true, cloudIdentity = true }

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

      pgdb_host     = var.data.postgres_host
      pgdb_port     = tostring(var.data.postgres_port)
      pgdb_name     = var.data.postgres_db
      pg_pi_db_name = "plane_pi"

      # Managed OpenSearch, keyless: with no username/password and a pod identity, the api signs
      # with SigV4 (region from aws_region). Empty = search indexing off.
      opensearch_remote_url   = var.data.opensearch_enabled ? "https://${var.data.opensearch_endpoint}" : ""
      opensearch_index_prefix = var.data.opensearch_enabled ? var.data.opensearch_prefix : ""

      # silo publishes imports to worker_importers' queue (chart default: the main worker's).
      silo_envs = { importers_queue_name = "celery.importer" }

      email_service_envs = { smtp_domain = var.email.enabled && var.email.smtp_domain != null ? var.email.smtp_domain : "" }

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
      use_storage_proxy     = var.use_storage_proxy

      # As today's managed deployment: any attachment type can be uploaded.
      allow_all_attachment_types = true
      },
      # The api's and pi's vector indexes use this dimension, pi on or off: it must match the embedding model
      # pi uses (now or when turned on later), since the api creates its indexes once.
      { for k, v in { opensearch_embedding_dimension = tostring(var.pi.embedding_dimension) } : k => v if var.data.opensearch_enabled },
    )

    external_secrets = merge({
      database                = { secretName = "plane-db", usernameKey = "username", passwordKey = "password" }
      redis                   = { secretName = "plane-redis", passwordKey = "password" }
      rabbitmq                = { secretName = "plane-rabbitmq", usernameKey = "username", passwordKey = "password" }
      app_keys_existingSecret = "plane-app-keys"
      },
      { for k, v in { ai_providers_existingSecret = local.pi_ai_secret } : k => v if local.pi_api_keys },
    )

    # The api trusts forwarded client IPs only from TRUSTED_PROXY_IPS; the chart has no value for it
    # yet (chart change C-8). The proxies in front of the api sit in the VPC, so the VPC CIDR.
    extraEnv = concat([
      { name = "TRUSTED_PROXY_IPS", value = var.vpc_cidr },
      # Route import tasks to worker_importers' queue (the chart doesn't set this for the api).
      { name = "CELERY_IMPORTERS_QUEUE_ENABLED", value = "1" },
      ],
      # A moved 3.x installation's signature (env beats the chart's derived one): Plane needs it
      # once, to move the licences to the instance key it creates on first start.
      var.machine_signature == null ? [] : [{ name = "MACHINE_SIGNATURE", value = var.machine_signature }],
      local.pi_bedrock_env,
    )

    extraObjects = concat(
      [local.secret_store_object],
      values(local.external_secret),
      [local.app_keys_external_secret],
      # Plane AI's database, only when pi is on.
      var.enable_components.pi ? [local.db_init_job] : [],
      local.pi_api_keys ? [local.pi_api_keys_object] : [],
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
    terraform_data.addons_ready, module.plane_pod_identity, aws_opensearch_domain_policy.plane, aws_iam_role_policy.pi_connector,
  ]
}

# The email NLB the LB controller creates for the chart's email Service, found by its fixed name once
# the release (which waits for the LoadBalancer address) is installed.
data "aws_lb" "email" {
  count = var.email.load_balancer ? 1 : 0

  name = local.email_load_balancer_name

  depends_on = [helm_release.plane]
}
