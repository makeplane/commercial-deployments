# The plane-enterprise values the module generates. Mock providers: no GCP credentials or cluster needed.

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

  openai_key = "projects/plane-test-project/secrets/plane-openai-key"
  cohere_key = "projects/plane-test-project/secrets/plane-cohere-key"
  claude_key = "projects/plane-test-project/secrets/plane-claude-key"
}

run "gcs_workload_identity" {
  assert {
    condition     = yamldecode(output.plane_helm_values).env.storage_provider == "GCS"
    error_message = "Plane must use native GCS."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).env.gcs_bucket_name == "plane-test-uploads-abcd1234" && yamldecode(output.plane_helm_values).env.gcs_project_id == "plane-test-project"
    error_message = "GCS needs the bucket and the project."
  }
  assert {
    condition     = length([for k in keys(yamldecode(output.plane_helm_values).env) : k if startswith(k, "aws_") || startswith(k, "gcs_credentials")]) == 0
    error_message = "No AWS keys and no GCS key file: the pods use Workload Identity (Application Default Credentials)."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).serviceAccount.annotations["iam.gke.io/gcp-service-account"] == output.plane_service_account_email
    error_message = "Plane's ServiceAccount must be bound to the Plane Google service account."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).env.use_storage_proxy == false
    error_message = "Uploads go straight to the bucket with signed URLs by default."
  }
}

run "in_cluster_rabbitmq_and_opensearch" {
  assert {
    condition     = yamldecode(output.plane_helm_values).env.storageClass == "standard-rwo"
    error_message = "env.storageClass must be set, or the chart's OpenSearch volume never binds."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).services.rabbitmq.local_setup && yamldecode(output.plane_helm_values).services.rabbitmq.volumeSize == "10Gi"
    error_message = "RabbitMQ must run in the cluster on a 10 GiB volume."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).external_secrets.rabbitmq.secretName == "plane-rabbitmq"
    error_message = "The bundled RabbitMQ and the apps must read the External Secrets Secret (chart 3.12.2 contract)."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).services.opensearch.local_setup && yamldecode(output.plane_helm_values).external_secrets.opensearch_existingSecret == "plane-opensearch"
    error_message = "OpenSearch must run in the cluster and read the External Secrets Secret."
  }
  assert {
    condition = toset(keys(one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.target.template.data if o.metadata.name == "plane-opensearch"
      ]))) == toset([
      "OPENSEARCH_ENABLED", "OPENSEARCH_URL", "OPENSEARCH_USERNAME", "OPENSEARCH_PASSWORD",
      "OPENSEARCH_INITIAL_ADMIN_PASSWORD", "OPENSEARCH_INDEX_PREFIX", "OPENSEARCH_EMBEDDING_DIMENSION",
    ])
    error_message = "The OpenSearch ExternalSecret must render all seven OPENSEARCH_* keys the chart reads."
  }
}

run "secret_store_and_no_secret_values" {
  assert {
    condition     = one([for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.provider.gcpsm.projectID if o.kind == "SecretStore"]) == "plane-test-project"
    error_message = "The SecretStore must read Secret Manager in project_id."
  }
  assert {
    condition     = !contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.kind], "Job")
    error_message = "No DB-init Job on GCP: Terraform creates the plane_pi database."
  }
  assert {
    condition = (
      length([for k in keys(yamldecode(output.plane_helm_values).env) : k if strcontains(k, "password")]) == 0 &&
      !can(yamldecode(output.plane_helm_values).services.rabbitmq.default_password) &&
      !can(yamldecode(output.plane_helm_values).services.opensearch.password)
    )
    error_message = "plane_helm_values must carry no password: every credential comes from Secret Manager."
  }
  assert {
    condition     = one([for e in yamldecode(output.plane_helm_values).extraEnv : e.value if e.name == "TRUSTED_PROXIES"]) == "10.61.0.0/16"
    error_message = "The api must trust the pods range (Traefik reaches it from a pod IP)."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).services.email_service.service.annotations["networking.gke.io/load-balancer-ip-addresses"] == "plane-test-email"
    error_message = "The email Service must use the reserved email address."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).services.email_service.service.loadBalancerClass == "networking.gke.io/l4-regional-external"
    error_message = "The email Service must use the backend service-based load balancer class, or GKE ignores its static IP."
  }
  assert {
    condition = (
      yamldecode(output.plane_helm_values).services.pi.enabled == false &&
      !can(yamldecode(output.plane_helm_values).services.pi.ai_providers) &&
      !can(yamldecode(output.plane_helm_values).external_secrets.ai_providers_existingSecret) &&
      !can(yamldecode(output.plane_helm_values).services.opensearch.javaOpts) &&
      !can(yamldecode(output.plane_helm_values).services.opensearch.memoryLimit) &&
      !contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.metadata.name], "plane-ai-providers")
    )
    error_message = "Plane AI is off by default and renders nothing of its own."
  }
  assert {
    condition     = output.rabbitmq_endpoint == "plane-rabbitmq.plane.svc.cluster.local"
    error_message = "rabbitmq_endpoint must be the in-cluster RabbitMQ Service."
  }
}

run "redis_tls" {
  variables {
    redis = { transit_encryption = true }
  }

  override_module {
    target = module.data
    outputs = {
      postgres_instance_name = "plane-test-pg-abcd"
      postgres_host          = "10.60.32.3"
      redis_host             = "10.60.33.4"
      redis_port             = 6378
      bucket_name            = "plane-test-uploads-abcd1234"
      secret_ids             = { app_keys = "projects/plane-test-project/secrets/plane-test-plane-app-keys" }
      plane_inputs = {
        bucket_name        = "plane-test-uploads-abcd1234"
        postgres_host      = "10.60.32.3"
        postgres_port      = 5432
        postgres_db        = "plane"
        redis_host         = "10.60.33.4"
        redis_port         = 6378
        redis_tls          = true
        redis_ca           = "-----BEGIN CERTIFICATE-----\nMOCK\n-----END CERTIFICATE-----"
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

  assert {
    condition     = yamldecode(output.plane_helm_values).env.redis_ssl && yamldecode(output.plane_helm_values).env.redis_port == "6378"
    error_message = "Memorystore TLS is on port 6378."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).customCA.s3Secrets == [{ name = "plane-redis-ca", key = "ca.crt" }]
    error_message = "The Node.js services must trust Memorystore's server CA through customCA."
  }
  assert {
    condition     = contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.metadata.name if o.kind == "Secret"], "plane-redis-ca")
    error_message = "The server CA must be shipped as a Secret."
  }
}

run "opensearch_off" {
  variables {
    opensearch = { enabled = false }
  }

  override_module {
    target = module.data
    outputs = {
      postgres_instance_name = "plane-test-pg-abcd"
      postgres_host          = "10.60.32.3"
      redis_host             = "10.60.33.4"
      redis_port             = 6379
      bucket_name            = "plane-test-uploads-abcd1234"
      secret_ids             = { app_keys = "projects/plane-test-project/secrets/plane-test-plane-app-keys" }
      plane_inputs = {
        bucket_name        = "plane-test-uploads-abcd1234"
        postgres_host      = "10.60.32.3"
        postgres_port      = 5432
        postgres_db        = "plane"
        redis_host         = "10.60.33.4"
        redis_port         = 6379
        redis_tls          = false
        redis_ca           = null
        opensearch_enabled = false
        secret_names = {
          postgres = "plane-test-plane-db"
          redis    = "plane-test-plane-redis"
          rabbitmq = "plane-test-plane-rabbitmq"
          app_keys = "plane-test-plane-app-keys"
        }
      }
    }
  }

  assert {
    condition     = !yamldecode(output.plane_helm_values).services.opensearch.local_setup
    error_message = "opensearch.enabled = false must not run OpenSearch."
  }
  assert {
    condition     = !contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.metadata.name], "plane-opensearch")
    error_message = "No OpenSearch ExternalSecret without OpenSearch."
  }
  assert {
    condition     = !can(yamldecode(output.plane_helm_values).external_secrets.opensearch_existingSecret)
    error_message = "No OpenSearch Secret reference without OpenSearch."
  }
}

# The api sizes its search indexes with the embedding model's dimension, so it is rendered with pi off too.
run "embedding_dimension_default_pi_off" {
  assert {
    condition = one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.target.template.data.OPENSEARCH_EMBEDDING_DIMENSION if o.metadata.name == "plane-opensearch"
    ]) == "1536"
    error_message = "With pi off, the OpenSearch Secret must carry the default model's dimension (cohere/embed-v4.0, 1536)."
  }
  assert {
    condition     = !yamldecode(output.plane_helm_values).services.pi.enabled && !can(yamldecode(output.plane_helm_values).services.pi.ai_providers)
    error_message = "With pi off, no pi providers are rendered."
  }
}

run "embedding_dimension_follows_model_pi_off" {
  variables {
    pi = { api_keys = { embedding_model = "cohere/embed-english-v3.0" } }
  }

  assert {
    condition = one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.target.template.data.OPENSEARCH_EMBEDDING_DIMENSION if o.metadata.name == "plane-opensearch"
    ]) == "1024"
    error_message = "With pi off, the OpenSearch Secret must carry the chosen model's dimension (cohere/embed-english-v3.0, 1024)."
  }
}

run "pi_on_gcs" {
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi                = { api_keys = { chat_key_secret = var.openai_key, embedding_key_secret = var.cohere_key } }
  }

  assert {
    condition     = yamldecode(output.plane_helm_values).services.pi.enabled && yamldecode(output.plane_helm_values).env.storage_provider == "GCS"
    error_message = "Plane AI must run, on the GCS bucket."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).services.pi.ai_providers.embedding_model == { enabled = true, name = "cohere/embed-v4.0", embedding_dimension = 1536 }
    error_message = "Plane AI must embed with cohere/embed-v4.0 at 1536 dimensions by default."
  }
  assert {
    condition = one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.target.template.data.OPENSEARCH_EMBEDDING_DIMENSION if o.metadata.name == "plane-opensearch"
    ]) == "1536"
    error_message = "The OpenSearch Secret must carry the embedding model's dimension (1536)."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).external_secrets.ai_providers_existingSecret == "plane-ai-providers"
    error_message = "The pi workloads must read the provider keys from the plane-ai-providers Secret."
  }
  assert {
    condition = one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec if o.kind == "ExternalSecret" && o.metadata.name == "plane-ai-providers"
      ]) == {
      refreshInterval = "1h"
      secretStoreRef  = { name = "gcp-secret-manager", kind = "SecretStore" }
      target          = { name = "plane-ai-providers", creationPolicy = "Orphan" }
      data = [
        { secretKey = "COHERE_API_KEY", remoteRef = { key = "plane-cohere-key" } },
        { secretKey = "OPENAI_API_KEY", remoteRef = { key = "plane-openai-key" } },
      ]
    }
    error_message = "External Secrets must copy each key, by name, into the env var pi reads for its provider: OpenAI chat and Cohere embeddings by default."
  }
  assert {
    condition     = toset(distinct(values(local.pi_api_key_secrets))) == toset([var.openai_key, var.cohere_key])
    error_message = "External Secrets must be allowed to read both key secrets."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).services.opensearch.javaOpts == "-Xms1536m -Xmx1536m" && yamldecode(output.plane_helm_values).services.opensearch.memoryLimit == "3Gi"
    error_message = "With Plane AI, OpenSearch gets a 1.5 GB heap in a 3 GiB limit."
  }
}

run "pi_anthropic_chat" {
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi                = { api_keys = { chat_provider = "anthropic", chat_key_secret = var.claude_key, embedding_key_secret = var.cohere_key } }
  }

  assert {
    condition = toset(one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.data if o.metadata.name == "plane-ai-providers"
      ])) == toset([
      { secretKey = "CLAUDE_API_KEY", remoteRef = { key = "plane-claude-key" } },
      { secretKey = "COHERE_API_KEY", remoteRef = { key = "plane-cohere-key" } },
    ])
    error_message = "Anthropic chat reads its key from CLAUDE_API_KEY."
  }
}

run "pi_openai_both" {
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi = {
      api_keys = { chat_key_secret = var.openai_key, embedding_model = "openai/text-embedding-3-small", embedding_key_secret = var.openai_key }
    }
  }

  assert {
    condition = (
      one([for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.data if o.metadata.name == "plane-ai-providers"]) == [
        { secretKey = "OPENAI_API_KEY", remoteRef = { key = "plane-openai-key" } },
      ]
      && yamldecode(output.plane_helm_values).services.pi.ai_providers.embedding_model.name == "openai/text-embedding-3-small"
    )
    error_message = "OpenAI for both: one key, and the chosen embedding model."
  }
}

run "pi_embedding_dimension_follows_model" {
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi = {
      api_keys = { chat_key_secret = var.openai_key, embedding_model = "openai/text-embedding-3-large", embedding_key_secret = var.openai_key }
    }
  }

  assert {
    condition     = yamldecode(output.plane_helm_values).services.pi.ai_providers.embedding_model == { enabled = true, name = "openai/text-embedding-3-large", embedding_dimension = 3072 }
    error_message = "Plane AI must embed with the chosen model at its dimension (3072)."
  }
  assert {
    condition = one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.target.template.data.OPENSEARCH_EMBEDDING_DIMENSION if o.metadata.name == "plane-opensearch"
    ]) == "3072"
    error_message = "The OpenSearch Secret must carry the chosen model's dimension (3072)."
  }
}

run "reject_pi_without_opensearch" {
  command = plan
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi                = { api_keys = { chat_key_secret = var.openai_key, embedding_key_secret = var.cohere_key } }
    opensearch        = { enabled = false }
  }
  expect_failures = [var.enable_components]
}

run "reject_pi_without_keys" {
  command = plan
  variables {
    enable_components = { pi = true }
    plane_version     = "v99.0.0"
    pi                = { api_keys = { chat_key_secret = var.openai_key } }
  }
  expect_failures = [var.pi]
}

run "reject_pi_below_plane_version_floor" {
  command = plan
  variables {
    enable_components = { pi = true }
    pi                = { api_keys = { chat_key_secret = var.openai_key, embedding_key_secret = var.cohere_key } }
  }
  expect_failures = [var.plane_version]
}

run "pi_on_preview_build_tag" {
  command = plan
  variables {
    enable_components = { pi = true }
    plane_version     = "preview-abc1234"
    pi                = { api_keys = { chat_key_secret = var.openai_key, embedding_key_secret = var.cohere_key } }
  }
}

run "reject_openai_two_keys" {
  command = plan
  variables {
    pi = {
      api_keys = { chat_key_secret = var.openai_key, embedding_model = "openai/text-embedding-3-small", embedding_key_secret = var.cohere_key }
    }
  }
  expect_failures = [var.pi]
}

run "reject_secret_in_another_project" {
  command = plan
  variables {
    pi = { api_keys = { chat_key_secret = "projects/other-project/secrets/plane-openai-key", embedding_key_secret = var.cohere_key } }
  }
  expect_failures = [var.pi]
}

run "reject_bad_chat_provider" {
  command = plan
  variables {
    pi = { api_keys = { chat_provider = "groq" } }
  }
  expect_failures = [var.pi]
}

run "reject_bad_embedding_model" {
  command = plan
  variables {
    pi = { api_keys = { embedding_model = "bedrock/amazon.titan-embed-text-v2" } }
  }
  expect_failures = [var.pi]
}

run "reject_bad_zone" {
  command = plan
  variables {
    zones = ["europe-west1-b"]
  }
  expect_failures = [var.zones]
}

# Plane's Google service account: this bucket only, keyless signing, and only Plane's Kubernetes ServiceAccount.
run "plane_identity" {
  module {
    source = "./modules/plane"
  }
  variables {
    pods_cidr          = "10.61.0.0/16"
    plane_version      = "v4.0.1"
    chart_version      = "3.12.2"
    chart_repository   = "https://helm.plane.so/"
    chart_name         = "plane-enterprise"
    enable_components  = { silo = true, drawio = true, pi = false }
    tls_secret_name    = "plane-tls"
    ingress_enabled    = false
    acme_email         = null
    acme_server        = "https://acme-v02.api.letsencrypt.org/directory"
    use_storage_proxy  = false
    rabbitmq           = { volume_size_gb = 10 }
    opensearch         = { enabled = true, volume_size_gb = 20, index_prefix = "plane" }
    pi                 = { embedding_model = "cohere/embed-v4.0", embedding_dimension = 1536, api_key_secrets = {} }
    helm_timeout       = 3600
    plane_values       = ""
    addons_ready       = "ready"
    email_address_name = "plane-test-email"

    tls_certificate_secret = null
    email                  = { enabled = true, smtp_domain = "intake.plane.example.com", load_balancer = true, certificate_secret = null }
    data = {
      bucket_name        = "plane-test-uploads-abcd1234"
      postgres_host      = "10.60.32.3"
      postgres_port      = 5432
      postgres_db        = "plane"
      redis_host         = "10.60.33.4"
      redis_port         = 6379
      redis_tls          = false
      redis_ca           = null
      opensearch_enabled = true
      secret_names       = { postgres = "a", redis = "b", rabbitmq = "c", opensearch = "d", app_keys = "e" }
    }
  }

  assert {
    condition     = google_service_account_iam_member.plane_workload_identity.member == "serviceAccount:plane-test-project.svc.id.goog[plane/plane-srv-account]"
    error_message = "Only Plane's Kubernetes ServiceAccount may act as the Plane Google service account."
  }
  assert {
    condition     = toset([for m in google_storage_bucket_iam_member.plane : m.bucket]) == toset(["plane-test-uploads-abcd1234"])
    error_message = "Plane's storage roles must be on the uploads bucket only."
  }
  assert {
    condition     = google_service_account_iam_member.plane_token_creator.member == google_service_account.plane.member
    error_message = "Plane signs URLs as itself: TokenCreator on its own service account."
  }
}
