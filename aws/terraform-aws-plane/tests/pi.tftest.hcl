# Plane AI (enable_components.pi, pi): off by default; on, provider API keys (default) or Bedrock, and
# the input rules. Mock providers: no AWS credentials or cluster needed.
# Run: terraform init && terraform test

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:user/test" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
  mock_data "aws_iam_session_context" {
    defaults = { issuer_arn = "arn:aws:iam::123456789012:user/test" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_bedrock_inference_profile" {
    defaults = { arn = "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/mock" }
  }
}
mock_provider "helm" {}
mock_provider "random" {}
mock_provider "time" {}
mock_provider "tls" {}
mock_provider "null" {}

override_module {
  target = module.network
  outputs = {
    vpc_id             = "vpc-0123456789abcdef0"
    private_subnet_ids = ["subnet-0a", "subnet-0b", "subnet-0c"]
    public_subnet_ids  = ["subnet-1a", "subnet-1b", "subnet-1c"]
  }
}

override_module {
  target = module.cluster
  outputs = {
    cluster_name                       = "plane-test"
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw=="
    ready                              = "plane-test"
    node_security_group_id             = "sg-0123456789abcdef0"
  }
}

override_module {
  target = module.data
  outputs = {
    kms_key_arn   = "arn:aws:kms:us-east-1:123456789012:key/mock"
    postgres_host = "postgres.mock"
    redis_host    = "redis.mock"
    rabbitmq_host = "rabbitmq.mock"
    bucket_name   = "plane-test-uploads"
    secret_arns = {
      postgres = "arn:aws:secretsmanager:us-east-1:123456789012:secret:postgres"
      redis    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:redis"
      rabbitmq = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rabbitmq"
      app_keys = "arn:aws:secretsmanager:us-east-1:123456789012:secret:app-keys"
    }
    plane_inputs = {
      kms_key_arn            = "arn:aws:kms:us-east-1:123456789012:key/mock"
      bucket_name            = "plane-test-uploads"
      bucket_arn             = "arn:aws:s3:::plane-test-uploads"
      postgres_host          = "postgres.mock"
      postgres_port          = 5432
      postgres_db            = "plane"
      postgres_secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:postgres"
      redis_host             = "redis.mock"
      redis_port             = 6379
      redis_secret_arn       = "arn:aws:secretsmanager:us-east-1:123456789012:secret:redis"
      rabbitmq_host          = "rabbitmq.mock"
      rabbitmq_port          = 5671
      rabbitmq_secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rabbitmq"
      app_keys_secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:app-keys"
      app_key_names          = ["SECRET_KEY", "AES_SECRET_KEY"]
      opensearch_enabled     = true
      opensearch_endpoint    = "opensearch.mock"
      opensearch_domain_name = "plane-test"
      opensearch_domain_arn  = "arn:aws:es:us-east-1:123456789012:domain/plane-test"
      opensearch_prefix      = "plane"
    }
  }
}

variables {
  name   = "plane-test"
  domain = "plane.example.com"

  openai_key = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/openai-key-AbCdEf"
  cohere_key = "arn:aws:secretsmanager:us-east-1:123456789012:secret:plane/cohere-key-AbCdEf"
}

run "pi_off_unchanged" {
  assert {
    condition     = !yamldecode(output.plane_helm_values).services.pi.enabled && !can(yamldecode(output.plane_helm_values).services.pi.ai_providers)
    error_message = "With pi off, pi must stay disabled with no AI provider settings."
  }
  assert {
    condition = (
      length(yamldecode(output.plane_helm_values).extraEnv) == 2
      && !can(yamldecode(output.plane_helm_values).external_secrets.ai_providers_existingSecret)
    )
    error_message = "With pi off, extraEnv and external_secrets must be as before."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).env.opensearch_embedding_dimension == "1536"
    error_message = "With pi off, the api's indexes must still get the default embedding model's dimension (cohere/embed-v4.0, 1536)."
  }
  assert {
    condition = length([
      for o in yamldecode(output.plane_helm_values).extraObjects : o if contains(["plane-pi-db-init", "plane-ai-providers"], o.metadata.name)
    ]) == 0
    error_message = "With pi off, no Plane AI objects."
  }
}

run "pi_off_bedrock_dimension" {
  variables {
    pi = { provider = "bedrock" }
  }

  assert {
    condition     = yamldecode(output.plane_helm_values).env.opensearch_embedding_dimension == "1024"
    error_message = "With pi off, the dimension must follow the selected Bedrock embedding model (Titan v2, 1024)."
  }
  assert {
    condition = (
      !yamldecode(output.plane_helm_values).services.pi.enabled && !can(yamldecode(output.plane_helm_values).services.pi.ai_providers)
      && length(yamldecode(output.plane_helm_values).extraEnv) == 2
    )
    error_message = "With pi off, Bedrock must render no AI provider settings or profiles."
  }
}

run "pi_off_without_opensearch" {
  variables {
    opensearch = { enabled = false }
  }
  override_module {
    target = module.data
    outputs = {
      kms_key_arn   = "arn:aws:kms:us-east-1:123456789012:key/mock"
      postgres_host = "postgres.mock"
      redis_host    = "redis.mock"
      rabbitmq_host = "rabbitmq.mock"
      bucket_name   = "plane-test-uploads"
      secret_arns = {
        postgres = "arn:aws:secretsmanager:us-east-1:123456789012:secret:postgres"
        redis    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:redis"
        rabbitmq = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rabbitmq"
        app_keys = "arn:aws:secretsmanager:us-east-1:123456789012:secret:app-keys"
      }
      plane_inputs = {
        kms_key_arn            = "arn:aws:kms:us-east-1:123456789012:key/mock"
        bucket_name            = "plane-test-uploads"
        bucket_arn             = "arn:aws:s3:::plane-test-uploads"
        postgres_host          = "postgres.mock"
        postgres_port          = 5432
        postgres_db            = "plane"
        postgres_secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:postgres"
        redis_host             = "redis.mock"
        redis_port             = 6379
        redis_secret_arn       = "arn:aws:secretsmanager:us-east-1:123456789012:secret:redis"
        rabbitmq_host          = "rabbitmq.mock"
        rabbitmq_port          = 5671
        rabbitmq_secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rabbitmq"
        app_keys_secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:app-keys"
        app_key_names          = ["SECRET_KEY", "AES_SECRET_KEY"]
        opensearch_enabled     = false
        opensearch_endpoint    = null
        opensearch_domain_name = null
        opensearch_domain_arn  = null
        opensearch_prefix      = "plane"
      }
    }
  }

  assert {
    condition     = !can(yamldecode(output.plane_helm_values).env.opensearch_embedding_dimension)
    error_message = "Without OpenSearch, no embedding dimension."
  }
}

run "pi_default_api_keys" {
  variables {
    enable_components = { pi = true }
    pi                = { api_keys = { chat_key_secret_arn = var.openai_key, embedding_key_secret_arn = var.cohere_key } }
  }

  assert {
    condition = (
      yamldecode(output.plane_helm_values).services.pi.ai_providers.embedding_model.name == "cohere/embed-v4.0"
      && yamldecode(output.plane_helm_values).external_secrets.ai_providers_existingSecret != null
    )
    error_message = "Without a provider, Plane AI must use the API keys: Cohere embeddings and OpenAI chat."
  }
}

run "reject_pi_without_keys" {
  command = plan
  variables {
    enable_components = { pi = true }
  }
  expect_failures = [var.pi]
}

run "pi_bedrock_defaults" {
  variables {
    enable_components = { pi = true }
    pi                = { provider = "bedrock" }
  }

  assert {
    condition = yamldecode(output.plane_helm_values).services.pi.ai_providers == {
      embedding_model = {
        enabled             = true
        name                = "bedrock/amazon.titan-embed-text-v2"
        embedding_dimension = 1024
        aws_region          = "us-east-1"
      }
      custom_llm = {
        enabled    = true
        provider   = "bedrock"
        model_key  = "global.anthropic.claude-sonnet-4-6"
        name       = "Claude (Amazon Bedrock)"
        max_tokens = 64000
        aws_region = "us-east-1"
      }
      bedrock = {
        enabled               = true
        inference_profile_arn = "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/mock"
        region                = "us-east-1"
      }
    }
    error_message = "Bedrock defaults: Titan Text Embeddings v2 and Claude Sonnet 4.6 (global profile), both through the module's profiles."
  }
  assert {
    condition     = yamldecode(output.plane_helm_values).env.opensearch_embedding_dimension == "1024"
    error_message = "The OpenSearch Secret's dimension (it wins over the ConfigMap's) must match the model."
  }
  assert {
    condition = (
      contains(yamldecode(output.plane_helm_values).extraEnv, { name = "BEDROCK_EMBEDDING_INFERENCE_PROFILE_ARN", value = "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/mock" })
      && contains(yamldecode(output.plane_helm_values).extraEnv, { name = "AWS_OPENSEARCH_CONNECTOR_ROLE_ARN", value = "arn:aws:iam::123456789012:role/mock" })
    )
    error_message = "pi must get the embeddings profile and the connector role."
  }
  assert {
    condition = (
      !can(yamldecode(output.plane_helm_values).external_secrets.ai_providers_existingSecret)
      && contains([for o in yamldecode(output.plane_helm_values).extraObjects : o.metadata.name], "plane-pi-db-init")
    )
    error_message = "Bedrock needs no API key Secret; pi needs its database Job."
  }
}

run "pi_bedrock_custom_models" {
  variables {
    enable_components = { pi = true }
    pi = {
      provider = "bedrock"
      bedrock  = { embedding_model = "bedrock/cohere.embed-multilingual-v3", chat_model_id = "eu.anthropic.claude-sonnet-4-6", chat_max_tokens = 32000 }
    }
  }

  assert {
    condition = (
      yamldecode(output.plane_helm_values).services.pi.ai_providers.embedding_model.name == "bedrock/cohere.embed-multilingual-v3"
      && yamldecode(output.plane_helm_values).services.pi.ai_providers.custom_llm.model_key == "eu.anthropic.claude-sonnet-4-6"
      && yamldecode(output.plane_helm_values).services.pi.ai_providers.custom_llm.max_tokens == 32000
    )
    error_message = "Chosen Bedrock models must reach pi."
  }
}

run "pi_api_keys" {
  variables {
    enable_components = { pi = true }
    pi                = { provider = "api_keys", api_keys = { chat_key_secret_arn = var.openai_key, embedding_key_secret_arn = var.cohere_key } }
  }

  assert {
    condition     = yamldecode(output.plane_helm_values).external_secrets.ai_providers_existingSecret == "plane-ai-providers"
    error_message = "pi must read the provider keys from the synced Secret."
  }
  assert {
    condition = toset(one([
      for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.data if o.metadata.name == "plane-ai-providers"
      ])) == toset([
      { secretKey = "OPENAI_API_KEY", remoteRef = { key = var.openai_key } },
      { secretKey = "COHERE_API_KEY", remoteRef = { key = var.cohere_key } },
    ])
    error_message = "External Secrets must copy each key into the env var pi reads for its provider."
  }
  assert {
    condition = yamldecode(output.plane_helm_values).services.pi.ai_providers == {
      embedding_model = { enabled = true, name = "cohere/embed-v4.0", embedding_dimension = 1536, aws_region = "us-east-1" }
    }
    error_message = "With keys: Cohere embed-v4.0 embeddings and no Bedrock chat."
  }
  assert {
    condition     = length(yamldecode(output.plane_helm_values).extraEnv) == 2
    error_message = "With keys: no Bedrock profile or connector role."
  }
}

run "pi_api_keys_openai_both" {
  variables {
    enable_components = { pi = true }
    pi = {
      provider = "api_keys"
      api_keys = { chat_key_secret_arn = var.openai_key, embedding_model = "openai/text-embedding-3-large", embedding_key_secret_arn = var.openai_key }
    }
  }

  assert {
    condition = (
      one([for o in yamldecode(output.plane_helm_values).extraObjects : o.spec.data if o.metadata.name == "plane-ai-providers"]) == [
        { secretKey = "OPENAI_API_KEY", remoteRef = { key = var.openai_key } },
      ]
      && yamldecode(output.plane_helm_values).env.opensearch_embedding_dimension == "3072"
    )
    error_message = "OpenAI for both: one key, and the model's dimension."
  }
}

run "reject_pi_without_opensearch" {
  command = plan
  variables {
    enable_components = { pi = true }
    opensearch        = { enabled = false }
    pi                = { api_keys = { chat_key_secret_arn = var.openai_key, embedding_key_secret_arn = var.cohere_key } }
  }
  expect_failures = [var.enable_components]
}

run "reject_unknown_provider" {
  command = plan
  variables {
    enable_components = { pi = true }
    pi                = { provider = "azure" }
  }
  expect_failures = [var.pi]
}

run "reject_bedrock_non_bedrock_embeddings" {
  command = plan
  variables {
    enable_components = { pi = true }
    pi                = { provider = "bedrock", bedrock = { embedding_model = "cohere/embed-v4.0" } }
  }
  expect_failures = [var.pi]
}

run "reject_bedrock_chat_not_claude" {
  command = plan
  variables {
    enable_components = { pi = true }
    pi                = { provider = "bedrock", bedrock = { chat_model_id = "amazon.nova-pro-v1:0" } }
  }
  expect_failures = [var.pi]
}

run "reject_mixed_modes" {
  command = plan
  variables {
    enable_components = { pi = true }
    pi                = { provider = "bedrock", api_keys = { chat_key_secret_arn = var.openai_key } }
  }
  expect_failures = [var.pi]
}

run "reject_api_keys_missing_key" {
  command = plan
  variables {
    enable_components = { pi = true }
    pi                = { provider = "api_keys", api_keys = { chat_key_secret_arn = var.openai_key } }
  }
  expect_failures = [var.pi]
}

run "reject_api_keys_bedrock_embeddings" {
  command = plan
  variables {
    enable_components = { pi = true }
    pi = {
      provider = "api_keys"
      api_keys = { chat_key_secret_arn = var.openai_key, embedding_model = "bedrock/amazon.titan-embed-text-v2", embedding_key_secret_arn = var.cohere_key }
    }
  }
  expect_failures = [var.pi]
}

run "reject_openai_two_keys" {
  command = plan
  variables {
    enable_components = { pi = true }
    pi = {
      provider = "api_keys"
      api_keys = { chat_key_secret_arn = var.openai_key, embedding_model = "openai/text-embedding-3-small", embedding_key_secret_arn = var.cohere_key }
    }
  }
  expect_failures = [var.pi]
}

# IAM and inference profiles, on the plane module alone.

run "iam_bedrock" {
  module {
    source = "./modules/plane"
  }
  variables {
    region                     = "us-east-1"
    cluster_name               = "plane-test"
    plane_version              = "v4.0.1"
    chart_version              = "3.11.3"
    vpc_cidr                   = "10.60.0.0/16"
    enable_components          = { silo = true, drawio = true, pi = true }
    tls_secret_name            = "plane-tls"
    ingress_enabled            = false
    tls_certificate_secret_arn = null
    email                      = { enabled = false, smtp_domain = null, load_balancer = false, certificate_secret_arn = null }
    public_subnet_ids          = []
    chart_repository           = "https://helm.plane.so/"
    chart_name                 = "plane-enterprise"
    acme_email                 = null
    acme_server                = "https://acme-v02.api.letsencrypt.org/directory"
    helm_timeout               = 3600
    plane_values               = ""
    addons_ready               = "ready"
    machine_signature          = null
    tags                       = {}
    data = {
      kms_key_arn            = "arn:aws:kms:us-east-1:123456789012:key/mock"
      bucket_name            = "plane-test-uploads"
      bucket_arn             = "arn:aws:s3:::plane-test-uploads"
      postgres_host          = "postgres.mock"
      postgres_port          = 5432
      postgres_db            = "plane"
      postgres_secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:postgres"
      redis_host             = "redis.mock"
      redis_port             = 6379
      redis_secret_arn       = "arn:aws:secretsmanager:us-east-1:123456789012:secret:redis"
      rabbitmq_host          = "rabbitmq.mock"
      rabbitmq_port          = 5671
      rabbitmq_secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rabbitmq"
      app_keys_secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:app-keys"
      app_key_names          = ["SECRET_KEY", "AES_SECRET_KEY"]
      opensearch_enabled     = true
      opensearch_endpoint    = "opensearch.mock"
      opensearch_domain_name = "plane-test"
      opensearch_domain_arn  = "arn:aws:es:us-east-1:123456789012:domain/plane-test"
      opensearch_prefix      = "plane"
    }
    pi = {
      mode                = "bedrock"
      embedding_model     = "bedrock/amazon.titan-embed-text-v2"
      embedding_dimension = 1024
      bedrock = {
        embedding_model    = "bedrock/amazon.titan-embed-text-v2"
        embedding_model_id = "amazon.titan-embed-text-v2:0"
        chat_model_id      = "global.anthropic.claude-sonnet-4-6"
        chat_model_name    = "Claude (Amazon Bedrock)"
        chat_max_tokens    = 64000
      }
      api_key_secrets = {}
    }
  }

  assert {
    condition = (
      aws_bedrock_inference_profile.pi["embeddings"].model_source[0].copy_from == "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
      && aws_bedrock_inference_profile.pi["chat"].model_source[0].copy_from == "arn:aws:bedrock:us-east-1:123456789012:inference-profile/global.anthropic.claude-sonnet-4-6"
    )
    error_message = "Profiles copy the in-region embedding model and the chat model's cross-Region profile."
  }
  assert {
    condition     = length(aws_iam_role.pi_connector) == 1 && length(aws_iam_role_policy.pi_connector) == 1
    error_message = "Bedrock embeddings need the connector role and its policy."
  }
  assert {
    condition = (
      one(data.aws_iam_policy_document.pi_connector_trust[0].statement[0].principals).identifiers == toset(["opensearchservice.amazonaws.com"])
      && toset([for c in data.aws_iam_policy_document.pi_connector_trust[0].statement[0].condition : "${c.variable}=${join(",", c.values)}"]) == toset([
        "aws:SourceAccount=123456789012", "aws:SourceArn=arn:aws:es:us-east-1:123456789012:domain/plane-test",
      ])
    )
    error_message = "Only the module's OpenSearch domain may assume the connector role."
  }
  assert {
    condition = (
      data.aws_iam_policy_document.pi_connector[0].statement[0].resources == toset(["arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/mock"])
      && data.aws_iam_policy_document.pi_connector[0].statement[2].resources == toset(["arn:aws:es:us-east-1:123456789012:domain/plane-test/*"])
    )
    error_message = "The connector role may invoke only the embeddings profile (and its model through it) and set up ML on the domain."
  }
  assert {
    condition     = toset(local.pi_profile_arns.chat) == toset(["arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/mock", "arn:aws:bedrock:us-east-1:123456789012:inference-profile/global.anthropic.claude-sonnet-4-6"])
    error_message = "Plane's role may invoke the chat profile and the cross-Region profile it copies."
  }
  assert {
    condition     = length(data.aws_iam_policy_document.opensearch[0].statement) == 2
    error_message = "The domain policy must also allow the connector role."
  }
}

run "iam_api_keys" {
  command = plan
  module {
    source = "./modules/plane"
  }
  variables {
    region                     = "us-east-1"
    cluster_name               = "plane-test"
    plane_version              = "v4.0.1"
    chart_version              = "3.11.3"
    vpc_cidr                   = "10.60.0.0/16"
    enable_components          = { silo = true, drawio = true, pi = true }
    tls_secret_name            = "plane-tls"
    ingress_enabled            = false
    tls_certificate_secret_arn = null
    email                      = { enabled = false, smtp_domain = null, load_balancer = false, certificate_secret_arn = null }
    public_subnet_ids          = []
    chart_repository           = "https://helm.plane.so/"
    chart_name                 = "plane-enterprise"
    acme_email                 = null
    acme_server                = "https://acme-v02.api.letsencrypt.org/directory"
    helm_timeout               = 3600
    plane_values               = ""
    addons_ready               = "ready"
    machine_signature          = null
    tags                       = {}
    data = {
      kms_key_arn            = "arn:aws:kms:us-east-1:123456789012:key/mock"
      bucket_name            = "plane-test-uploads"
      bucket_arn             = "arn:aws:s3:::plane-test-uploads"
      postgres_host          = "postgres.mock"
      postgres_port          = 5432
      postgres_db            = "plane"
      postgres_secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:postgres"
      redis_host             = "redis.mock"
      redis_port             = 6379
      redis_secret_arn       = "arn:aws:secretsmanager:us-east-1:123456789012:secret:redis"
      rabbitmq_host          = "rabbitmq.mock"
      rabbitmq_port          = 5671
      rabbitmq_secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rabbitmq"
      app_keys_secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:app-keys"
      app_key_names          = ["SECRET_KEY", "AES_SECRET_KEY"]
      opensearch_enabled     = true
      opensearch_endpoint    = "opensearch.mock"
      opensearch_domain_name = "plane-test"
      opensearch_domain_arn  = "arn:aws:es:us-east-1:123456789012:domain/plane-test"
      opensearch_prefix      = "plane"
    }
    pi = {
      mode                = "api_keys"
      embedding_model     = "cohere/embed-v4.0"
      embedding_dimension = 1536
      bedrock             = null
      api_key_secrets     = { OPENAI_API_KEY = "arn:aws:secretsmanager:us-east-1:123456789012:secret:a", COHERE_API_KEY = "arn:aws:secretsmanager:us-east-1:123456789012:secret:b" }
    }
  }

  assert {
    condition = (
      length(aws_iam_role.pi_connector) == 0 && length(aws_bedrock_inference_profile.pi) == 0
      && length(data.aws_iam_policy_document.opensearch[0].statement) == 1
    )
    error_message = "With keys: no Bedrock profiles or connector role, and the domain policy is unchanged."
  }
}
