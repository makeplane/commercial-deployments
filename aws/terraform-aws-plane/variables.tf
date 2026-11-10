################################################################################
# Common (same names on the AWS, GCP and Azure modules)
################################################################################

variable "name" {
  description = "Prefix for every resource the module creates. Lowercase letters, digits and hyphens, at most 20 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", var.name))
    error_message = "name must be 3-20 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "domain" {
  description = "FQDN Plane is served on. It is also the licence domain and part of the instance identity, so it must never change after install."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", var.domain))
    error_message = "domain must be a lowercase FQDN, e.g. plane.example.com."
  }
}

variable "deployment_mode" {
  description = "How Plane runs. Only \"eks\" is available in this release; \"docker\" (one EC2 instance with prime-cli) comes in v0.2."
  type        = string
  default     = "eks"
  nullable    = false

  validation {
    condition     = contains(["eks"], var.deployment_mode)
    error_message = "Only deployment_mode = \"eks\" is supported in this release."
  }
}

variable "plane_version" {
  description = "Plane release to install (chart planeVersion)."
  type        = string
  default     = "v4.0.1"
  nullable    = false
}

variable "chart_version" {
  description = "plane-enterprise Helm chart version. 3.11.3 or later (configurable email Service)."
  type        = string
  default     = "3.11.3"
  nullable    = false
}

variable "chart_repository" {
  description = "Helm repository of the plane-enterprise chart. Override only to test a preview build."
  type        = string
  default     = "https://helm.plane.so/"
  nullable    = false
}

variable "chart_name" {
  description = "Chart name in chart_repository (preview builds are named <commit>-plane-enterprise)."
  type        = string
  default     = "plane-enterprise"
  nullable    = false
}

variable "acme_email" {
  description = <<-EOT
    Path A (ingress.mode = "automated"), variant A.1: the Let's Encrypt account email. cert-manager issues the web
    certificate with HTTP-01 through Traefik: Plane must be public on port 80, and the certificate is issued once your
    DNS record for domain points at load_balancer_dns_name. Leave null for your own certificates
    (ingress.tls_certificate_secret_arn, variant A.2) or for path B.
  EOT
  type        = string
  default     = null
}

variable "acme_server" {
  description = "ACME directory URL. Use the Let's Encrypt staging URL for tests to avoid rate limits."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
  nullable    = false
}


variable "enable_components" {
  description = "Optional Plane workloads. pi is Plane AI (off by default); its models are set with the pi input: OpenAI and Cohere API keys from Secrets Manager by default, or Amazon Bedrock (keyless)."
  type = object({
    silo   = optional(bool, true)
    drawio = optional(bool, true)
    pi     = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.enable_components.pi || var.opensearch.enabled
    error_message = "Plane AI (enable_components.pi) needs OpenSearch (opensearch.enabled = true): its search indexes and embeddings live there."
  }
}

variable "pi" {
  description = <<-EOT
    Plane AI's models, used when enable_components.pi = true (needs OpenSearch). The module sets up semantic search
    (pi creates the embedding model in OpenSearch at startup) and a chat model. provider = "api_keys" (default): one
    chat key and embeddings on Cohere (api_keys.embedding_model, cohere/embed-v4.0). api_keys.chat_provider picks the
    chat key: a vendor ("openai", default; "anthropic", "xai", "baseten" or "meta"; Plane AI offers that vendor's
    built-in models) or "custom": your own model on any OpenAI-compatible API (pi's custom LLM). custom requires the
    OpenAI Chat Completions API at api_keys.chat_base_url (e.g. https://host/v1 serving /chat/completions, bearer
    key) and api_keys.chat_model (the model ID it expects); optional chat_model_name and chat_max_tokens (default
    128000). These four are only for custom. Both keys are required, each a Secrets Manager secret in this account
    and region (full ARN; encrypted with aws/secretsmanager or this module's KMS key): plain text, or JSON with
    *_key_json_field naming the field (one JSON secret can hold both). provider = "bedrock" (alternative): keyless
    Amazon Bedrock through Plane's Pod Identity role; the module creates an application inference profile for each
    model from bedrock.embedding_model (one of Plane AI's Bedrock embedding models) and bedrock.chat_model_id (an
    Anthropic Claude cross-Region inference profile ID, global. or a geography prefix such as us. or eu.; Plane AI
    calls it with the Anthropic API). The models must be available to the account in this region (Anthropic: submit
    the use case form once). Choose the provider and embedding model before the first install, even if Plane AI is
    turned on later: Plane's search indexes are created with its dimension, so changing it afterwards needs Plane's
    search indexes and Plane AI's indexes recreated.
  EOT
  type = object({
    provider = optional(string, "api_keys")
    api_keys = optional(object({
      chat_provider            = optional(string, "openai")
      chat_key_secret_arn      = optional(string)
      chat_key_json_field      = optional(string)
      chat_base_url            = optional(string)
      chat_model               = optional(string)
      chat_model_name          = optional(string)
      chat_max_tokens          = optional(number)
      embedding_model          = optional(string, "cohere/embed-v4.0")
      embedding_key_secret_arn = optional(string)
      embedding_key_json_field = optional(string)
    }), {})
    bedrock = optional(object({
      embedding_model = optional(string, "bedrock/amazon.titan-embed-text-v2")
      chat_model_id   = optional(string, "global.anthropic.claude-sonnet-4-6")
      chat_model_name = optional(string, "Claude (Amazon Bedrock)")
      chat_max_tokens = optional(number, 64000)
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["api_keys", "bedrock"], var.pi.provider)
    error_message = "pi.provider must be \"api_keys\" (default) or \"bedrock\"."
  }
  validation {
    condition     = var.pi.provider != "bedrock" || contains(keys(local.pi_bedrock_embedding_models), var.pi.bedrock.embedding_model)
    error_message = "pi.bedrock.embedding_model must be one of: ${join(", ", keys(local.pi_bedrock_embedding_models))}."
  }
  validation {
    condition     = var.pi.provider != "bedrock" || can(regex("^(global|us|us-gov|eu|apac|jp|au|ca|in)\\.anthropic\\.claude-[a-z0-9.:-]+$", var.pi.bedrock.chat_model_id))
    error_message = "pi.bedrock.chat_model_id must be an Anthropic Claude cross-Region inference profile ID: global. or a geography prefix (us., us-gov., eu., apac., jp., au., ca., in.) before the model ID, e.g. \"global.anthropic.claude-sonnet-4-6\" or \"eu.anthropic.claude-sonnet-4-6\". A bare anthropic.claude-* ID isn't accepted: current Claude models aren't served on demand in a single region."
  }
  validation {
    condition     = var.pi.provider != "bedrock" || (var.pi.api_keys.chat_key_secret_arn == null && var.pi.api_keys.embedding_key_secret_arn == null)
    error_message = "pi.api_keys secrets are only used with pi.provider = \"api_keys\"."
  }
  validation {
    condition     = !var.enable_components.pi || var.pi.provider != "api_keys" || (var.pi.api_keys.chat_key_secret_arn != null && var.pi.api_keys.embedding_key_secret_arn != null)
    error_message = "Plane AI with provider API keys (the default) needs pi.api_keys.chat_key_secret_arn (the chat key) and pi.api_keys.embedding_key_secret_arn (the Cohere key)."
  }
  validation {
    condition     = contains(keys(local.pi_chat_key_envs), var.pi.api_keys.chat_provider)
    error_message = "pi.api_keys.chat_provider must be one of: ${join(", ", keys(local.pi_chat_key_envs))}."
  }
  validation {
    condition = var.pi.api_keys.chat_provider == "custom" || alltrue([
      for v in [var.pi.api_keys.chat_base_url, var.pi.api_keys.chat_model, var.pi.api_keys.chat_model_name, var.pi.api_keys.chat_max_tokens] : v == null
    ])
    error_message = "pi.api_keys.chat_base_url, chat_model, chat_model_name and chat_max_tokens are only for chat_provider = \"custom\" (your own model on any OpenAI-compatible API). With a vendor key, Plane AI offers that vendor's built-in models: leave them unset."
  }
  validation {
    condition     = !var.enable_components.pi || var.pi.provider != "api_keys" || var.pi.api_keys.chat_provider != "custom" || (var.pi.api_keys.chat_base_url != null && var.pi.api_keys.chat_model != null)
    error_message = "pi.api_keys.chat_provider = \"custom\" needs pi.api_keys.chat_base_url (the base URL of an OpenAI-compatible API) and pi.api_keys.chat_model (the model ID it expects)."
  }
  validation {
    condition     = var.pi.api_keys.chat_base_url == null || can(regex("^https?://[^\\s/]+(/\\S*)?$", var.pi.api_keys.chat_base_url))
    error_message = "pi.api_keys.chat_base_url must be the base URL of an OpenAI-compatible API (OpenAI Chat Completions), e.g. \"https://my-llm.example.com/v1\"."
  }
  validation {
    condition     = var.pi.api_keys.chat_model == null || try(length(trimspace(var.pi.api_keys.chat_model)) > 0, false)
    error_message = "pi.api_keys.chat_model must be the model ID the OpenAI-compatible API expects, e.g. \"gpt-oss-120b\"."
  }
  validation {
    condition     = var.pi.api_keys.chat_max_tokens == null || try(var.pi.api_keys.chat_max_tokens >= 1000 && floor(var.pi.api_keys.chat_max_tokens) == var.pi.api_keys.chat_max_tokens, false)
    error_message = "pi.api_keys.chat_max_tokens must be a whole number of at least 1000: the chat model's context window."
  }
  validation {
    condition = alltrue([
      for f in [var.pi.api_keys.chat_key_json_field, var.pi.api_keys.embedding_key_json_field] : f == null || can(regex("^\\S+$", f))
    ])
    error_message = "pi.api_keys.*_key_json_field must be the name of a field in the JSON secret (no spaces), or unset for a plain-text secret."
  }
  validation {
    condition     = contains([for m in keys(local.pi_embedding_dimensions) : m if startswith(m, "cohere/")], var.pi.api_keys.embedding_model)
    error_message = "pi.api_keys.embedding_model must be a Cohere model: ${join(", ", [for m in keys(local.pi_embedding_dimensions) : m if startswith(m, "cohere/")])}."
  }
  validation {
    condition     = var.pi.api_keys.chat_key_secret_arn == null || can(regex(local.secret_arn_regex, var.pi.api_keys.chat_key_secret_arn))
    error_message = "pi.api_keys.chat_key_secret_arn must be ${local.secret_arn_format}."
  }
  validation {
    condition     = var.pi.api_keys.embedding_key_secret_arn == null || can(regex(local.secret_arn_regex, var.pi.api_keys.embedding_key_secret_arn))
    error_message = "pi.api_keys.embedding_key_secret_arn must be ${local.secret_arn_format}."
  }
}

variable "tags" {
  description = "Tags applied to every AWS resource."
  type        = map(string)
  default     = {}
  nullable    = false
}

################################################################################
# DNS and TLS
################################################################################


variable "ingress" {
  description = <<-EOT
    How traffic reaches Plane. mode = "automated" (path A): the module installs Traefik behind an NLB, Plane's routes and
    the certificates (Let's Encrypt via acme_email, or your own via tls_certificate_secret_arn). mode = "none" (path B,
    default): the module installs no ingress controller or routes; you bring your controller, routes, certificate and
    DNS after the apply. The module configures no DNS: the records are yours in both paths (see the dns_records output).
    Path A only: allowed_cidrs (who can reach Plane), scheme (internet-facing or internal) and
    tls_certificate_secret_arn (the full ARN of a Secrets Manager secret in this account and region, with JSON keys
    "tls.crt" and "tls.key", full chain, encrypted with the default aws/secretsmanager key or this module's KMS key).
  EOT
  type = object({
    mode                       = optional(string, "none")
    allowed_cidrs              = optional(list(string), ["0.0.0.0/0"])
    scheme                     = optional(string, "internet-facing")
    tls_certificate_secret_arn = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["none", "automated"], var.ingress.mode)
    error_message = "ingress.mode must be \"automated\" (path A) or \"none\" (path B)."
  }
  validation {
    condition     = contains(["internet-facing", "internal"], var.ingress.scheme)
    error_message = "ingress.scheme must be \"internet-facing\" or \"internal\"."
  }
  validation {
    condition     = length(var.ingress.allowed_cidrs) > 0 && alltrue([for c in var.ingress.allowed_cidrs : can(regex(local.ipv4_cidr_regex, c)) && can(cidrhost(c, 0)) && try(cidrhost(c, 0) == split("/", c)[0], false)])
    error_message = "ingress.allowed_cidrs must list at least one IPv4 CIDR whose address is the start of the range (e.g. 203.0.113.0/24, or 203.0.113.10/32 for one address)."
  }
  validation {
    condition     = var.ingress.mode != "automated" || ((var.acme_email != null) != (var.ingress.tls_certificate_secret_arn != null))
    error_message = "Path A (ingress.mode = \"automated\") needs exactly one web certificate source: acme_email (Let's Encrypt) or ingress.tls_certificate_secret_arn (your own certificate)."
  }
  validation {
    condition     = !(var.ingress.mode == "automated" && var.acme_email != null) || (contains(var.ingress.allowed_cidrs, "0.0.0.0/0") && var.ingress.scheme == "internet-facing")
    error_message = "Let's Encrypt (acme_email) uses HTTP-01, which needs Plane reachable from the internet on port 80: ingress.allowed_cidrs must include 0.0.0.0/0 and ingress.scheme must be internet-facing. Use your own certificate (ingress.tls_certificate_secret_arn) to restrict access."
  }
  validation {
    condition     = var.ingress.tls_certificate_secret_arn == null || can(regex(local.secret_arn_regex, var.ingress.tls_certificate_secret_arn))
    error_message = "ingress.tls_certificate_secret_arn must be ${local.secret_arn_format}."
  }
}

variable "tls_secret_name" {
  description = "Path A: name of the Kubernetes TLS Secret in the plane namespace that Traefik serves. Written by cert-manager (acme_email) or by External Secrets from ingress.tls_certificate_secret_arn."
  type        = string
  default     = "plane-tls"
  nullable    = false
}

################################################################################
# Network
################################################################################

variable "vpc_cidr" {
  description = "CIDR of the VPC the module creates. Must not overlap networks you will peer or VPN with. The default avoids 10.0.0.0/16, the default of most VPC tooling and of the older aws/terraform module."
  type        = string
  default     = "10.60.0.0/16"
  nullable    = false

  validation {
    condition     = can(regex(local.ipv4_cidr_regex, var.vpc_cidr)) && can(cidrhost(var.vpc_cidr, 0)) && try(cidrhost(var.vpc_cidr, 0) == split("/", var.vpc_cidr)[0], false)
    error_message = "vpc_cidr must be an IPv4 CIDR whose address is the start of the range (e.g. 10.60.0.0/16)."
  }
  validation {
    condition     = try(tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 20, false)
    error_message = "vpc_cidr must be /16 to /20: AWS allows /16 at most, and the module splits it into /20-/24 subnets (one sixteenth each) whose addresses the EKS pods also use."
  }
}

variable "az_count" {
  description = "Availability zones to use. The RDS Multi-AZ DB cluster needs at least 3."
  type        = number
  default     = 3
  nullable    = false

  validation {
    condition     = var.az_count >= 3
    error_message = "az_count must be at least 3 (RDS Multi-AZ DB clusters need three AZs)."
  }
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cheaper, as today's module) instead of one per AZ."
  type        = bool
  default     = true
  nullable    = false
}

################################################################################
# EKS
################################################################################

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.36"
  nullable    = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. The private endpoint is always on. Restrict this to your office, VPN or CI ranges."
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = false

  validation {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0 && alltrue([for c in var.cluster_endpoint_public_access_cidrs : can(regex(local.ipv4_cidr_regex, c)) && can(cidrhost(c, 0)) && try(cidrhost(c, 0) == split("/", c)[0], false)])
    error_message = "cluster_endpoint_public_access_cidrs must list at least one IPv4 CIDR whose address is the start of the range (e.g. 203.0.113.0/24, or 203.0.113.10/32 for one address)."
  }
}

variable "cluster_admin_principal_arns" {
  description = "IAM role or user ARNs granted cluster-admin through EKS access entries (not STS assumed-role session ARNs). The identity running Terraform is added automatically: don't list it again."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.cluster_admin_principal_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/[A-Za-z0-9+=,.@_/-]+$", a))])
    error_message = "cluster_admin_principal_arns entries must be IAM role or user ARNs (arn:aws:iam::<account>:role/<name> or :user/<name>). For an assumed-role session (arn:aws:sts::...:assumed-role/<role>/<session>), use the role's ARN."
  }
  validation {
    condition     = length(distinct(var.cluster_admin_principal_arns)) == length(var.cluster_admin_principal_arns)
    error_message = "cluster_admin_principal_arns must not repeat an ARN (EKS allows one access entry per principal)."
  }
}

variable "node_group" {
  description = <<-EOT
    The managed node group: starts at desired_size nodes and can range from min_size to max_size (2 to 4 by default, as
    today). No node autoscaler in this release, so it stays at desired_size until scaled by hand (aws eks
    update-nodegroup-config --scaling-config desiredSize=N) or by an autoscaler added later. Terraform sets desired_size
    only at creation and leaves later changes alone.
  EOT
  type = object({
    instance_types = optional(list(string), ["m7a.xlarge"])
    min_size       = optional(number, 2)
    max_size       = optional(number, 4)
    desired_size   = optional(number, 2)
    disk_size_gb   = optional(number, 50)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.node_group.min_size >= 1 && var.node_group.min_size <= var.node_group.desired_size && var.node_group.desired_size <= var.node_group.max_size
    error_message = "node_group needs 1 <= min_size <= desired_size <= max_size."
  }
}

variable "addon_versions" {
  description = "EKS managed add-on versions. null for an add-on means the most recent version for kubernetes_version."
  type = object({
    vpc_cni                = optional(string, "v1.23.2-eksbuild.8")
    coredns                = optional(string, "v1.14.7-eksbuild.22")
    kube_proxy             = optional(string, "v1.36.0-eksbuild.58")
    eks_pod_identity_agent = optional(string, "v1.4.1-eksbuild.3")
    aws_ebs_csi_driver     = optional(string, "v1.67.2-eksbuild.1")
  })
  default  = {}
  nullable = false
}

variable "helm_timeout" {
  description = "Seconds to wait for the Plane Helm release. A fresh install's migrations take about 20 minutes."
  type        = number
  default     = 3600
  nullable    = false
}

variable "plane_values" {
  description = "Extra plane-enterprise chart values (YAML string), merged last. Never put secrets here: they end up in Terraform state and the Helm release."
  type        = string
  default     = ""
  nullable    = false
}

################################################################################
# Data services
################################################################################

variable "postgres" {
  description = <<-EOT
    RDS PostgreSQL Multi-AZ DB cluster (1 writer + 2 readable standbys), sized as today's module. storage_type: io1
    (default), io2 or gp3. iops: io1/io2 default 1000 (1000-256000); gp3 leaves it unset below 400 GiB (a fixed 3000),
    12000-64000 from 400 GiB. apply_immediately: false (default) leaves database changes to the maintenance window;
    set it true for a major version upgrade (engine_version 15.x to 16.x, see the README) and any change you want now.
  EOT
  type = object({
    engine_version        = optional(string, "15.19")
    instance_class        = optional(string, "db.m6gd.large")
    allocated_storage_gb  = optional(number, 100)
    storage_type          = optional(string, "io1")
    iops                  = optional(number)
    backup_retention_days = optional(number, 14)
    deletion_protection   = optional(bool, true)
    apply_immediately     = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.postgres.engine_version))
    error_message = "postgres.engine_version must be an RDS for PostgreSQL version such as 15.19 (major.minor)."
  }
  validation {
    condition     = contains(["io1", "io2", "gp3"], var.postgres.storage_type)
    error_message = "postgres.storage_type must be io1, io2 or gp3 (the storage types of RDS Multi-AZ DB clusters)."
  }
  validation {
    condition     = var.postgres.allocated_storage_gb >= (var.postgres.storage_type == "gp3" ? 20 : 100)
    error_message = "postgres.allocated_storage_gb must be at least 100 GiB for io1/io2, 20 GiB for gp3."
  }
  validation {
    condition = var.postgres.iops == null ? true : (
      var.postgres.storage_type == "gp3"
      ? var.postgres.allocated_storage_gb >= 400 && var.postgres.iops >= 12000 && var.postgres.iops <= 64000
      : var.postgres.iops >= 1000 && var.postgres.iops <= 256000
    )
    error_message = "postgres.iops: io1/io2 take 1000-256000 (default 1000); gp3 takes 12000-64000 and only from 400 GiB (below that it's a fixed 3000; leave iops unset)."
  }
  validation {
    condition     = var.postgres.storage_type != "io1" || coalesce(var.postgres.iops, 1000) <= 50 * var.postgres.allocated_storage_gb
    error_message = "postgres.iops on io1 can be at most 50 per GiB of postgres.allocated_storage_gb."
  }
}

variable "redis" {
  description = "ElastiCache Valkey with TLS, an AUTH token and at-rest encryption, as Plane's own production cache. replicas = 1 (default) adds a replica in another AZ with automatic failover; 0 is a single node."
  type = object({
    engine_version = optional(string, "8.2")
    node_type      = optional(string, "cache.t3.medium")
    replicas       = optional(number, 1)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.redis.replicas >= 0 && var.redis.replicas <= 5 && floor(var.redis.replicas) == var.redis.replicas
    error_message = "redis.replicas must be a whole number from 0 to 5 (ElastiCache allows up to 5 replicas per primary)."
  }
}

variable "rabbitmq" {
  description = "Amazon MQ for RabbitMQ."
  type = object({
    engine_version  = optional(string, "3.13")
    instance_type   = optional(string, "mq.m7g.medium")
    deployment_mode = optional(string, "CLUSTER_MULTI_AZ")
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["SINGLE_INSTANCE", "CLUSTER_MULTI_AZ"], var.rabbitmq.deployment_mode)
    error_message = "rabbitmq.deployment_mode must be SINGLE_INSTANCE or CLUSTER_MULTI_AZ."
  }
}

variable "opensearch" {
  description = <<-EOT
    Amazon OpenSearch Service for Plane's search, on by default as in today's deployments: a private domain in the VPC
    (HTTPS only, KMS, node-to-node encryption), reached by Plane with its Pod Identity role (SigV4, no passwords). The
    chart's Job creates the search indexes after every install and upgrade. enabled = false: Plane runs with search
    indexing off.
  EOT
  type = object({
    enabled        = optional(bool, true)
    engine_version = optional(string, "OpenSearch_2.19")
    instance_type  = optional(string, "r7g.large.search")
    instance_count = optional(number, 2)
    volume_size_gb = optional(number, 10)
    # Index names are "<index_prefix>_<name>", as today's deployments ("plane"). Changing it on a running install
    # needs the indexes created again and re-filled (manage_search_index index create + document index).
    index_prefix = optional(string, "plane")
  })
  default  = {}
  nullable = false
}

variable "email" {
  description = <<-EOT
    Plane's email service (inbound email to work items). On by default with its own internet-facing NLB (ports 25 SMTP,
    465 SMTPS, 587 submission), the sender's IP preserved. smtp_domain is the domain that receives mail (default
    "intake.<domain>"): create its MX record pointing at the email_load_balancer_dns_name output (see dns_records).
    Certificate: your own via certificate_secret_arn (a Secrets Manager secret like ingress.tls_certificate_secret_arn),
    else the email app's own self-signed certificate (fine for receiving mail). load_balancer = false keeps the
    service running with no load balancer (not reachable from the internet); enabled = false turns the service and
    its load balancer off. Needs plane-enterprise chart 3.11.3+.
  EOT
  type = object({
    enabled                = optional(bool, true)
    smtp_domain            = optional(string)
    load_balancer          = optional(bool, true)
    certificate_secret_arn = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.email.certificate_secret_arn == null || can(regex(local.secret_arn_regex, var.email.certificate_secret_arn))
    error_message = "email.certificate_secret_arn must be ${local.secret_arn_format}."
  }
}

variable "use_storage_proxy" {
  description = <<-EOT
    How browsers reach files in the uploads bucket. false (default): they upload and download directly from the bucket
    with signed URLs, and the bucket allows CORS from domain. true: work item attachments, editor images and similar go
    through Plane's api (Plane v4.0.1 or later), which reaches the bucket with its own IAM role. This adds load on the
    api and is subject to the ingress body limit, so size both for large files. silo, live and pi don't read this
    setting, and Plane AI keeps direct signed URLs in both modes, so the bucket keeps its CORS configuration either way.
  EOT
  type        = bool
  default     = false
  nullable    = false
}

variable "bucket_force_destroy" {
  description = "Allow terraform destroy to delete the uploads bucket even when it holds objects."
  type        = bool
  default     = false
  nullable    = false
}

################################################################################
# Moving an existing installation (docs/migration-guide.md)
################################################################################

variable "app_keys_secret_arn" {
  description = <<-EOT
    Use existing app keys instead of generating them: for moving an existing Plane installation, whose stored data
    and settings are encrypted with its keys. The full ARN of a Secrets Manager secret in the same account and region,
    encrypted with the default aws/secretsmanager key, holding a JSON object with all eight keys: SECRET_KEY,
    AES_SECRET_KEY, AES_SALT, LIVE_SERVER_SECRET_KEY, PI_INTERNAL_SECRET, SILO_HMAC_SECRET_KEY, CURSOR_WEBHOOK_SECRET
    and RUNNER_HMAC_SECRET_KEY. Plane doesn't start until the secret holds every key. The keys never pass through
    Terraform. Set it on the first apply only: adding or removing it later deletes or replaces the keys in use.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.app_keys_secret_arn == null || can(regex(local.secret_arn_regex, var.app_keys_secret_arn))
    error_message = "app_keys_secret_arn must be ${local.secret_arn_format}."
  }
}

variable "machine_signature" {
  description = <<-EOT
    Only when moving a Plane 3.x installation: its MACHINE_SIGNATURE. On its first start, Plane 4 moves the licences
    to a new instance key, and the licence server recognises the installation by its instance ID and this value. Leave
    null otherwise: the chart derives one from the licence server, domain, namespace and release.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.machine_signature == null || can(regex("^[A-Za-z0-9]{16,128}$", var.machine_signature))
    error_message = "machine_signature must be the existing installation's value as is: letters and digits only."
  }
}
