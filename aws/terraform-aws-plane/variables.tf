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
    (pi creates the embedding model in OpenSearch at startup) and a chat model. provider = "api_keys" (default): chat on
    OpenAI (api_keys.chat_provider; or Anthropic) and embeddings on Cohere (api_keys.embedding_model, cohere/embed-v4.0;
    or an OpenAI model). Both API keys are required: each is a plain-text Secrets Manager secret in this account and
    region (full ARN; encrypted with aws/secretsmanager or this module's KMS key; one secret for both when the provider
    is the same). provider = "bedrock" (alternative): keyless Amazon Bedrock through Plane's Pod Identity role; the
    module creates an application inference profile for each model from bedrock.embedding_model (one of Plane AI's
    Bedrock embedding models) and bedrock.chat_model_id (an Anthropic Claude model ID or cross-Region inference profile
    ID; Plane AI calls it with the Anthropic API). The models must be available to the account in this region
    (Anthropic: submit the use case form once). Choose the provider and embedding model before the first install, even
    if Plane AI is turned on later: Plane's search indexes are created with its dimension, so changing it afterwards
    needs Plane's search indexes and Plane AI's indexes recreated.
  EOT
  type = object({
    provider = optional(string, "api_keys")
    api_keys = optional(object({
      chat_provider            = optional(string, "openai")
      chat_key_secret_arn      = optional(string)
      embedding_model          = optional(string, "cohere/embed-v4.0")
      embedding_key_secret_arn = optional(string)
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
    condition     = var.pi.provider != "bedrock" || can(regex("^((us|us-gov|eu|apac|au|jp|ca|in|global)\\.)?anthropic\\.claude-[a-z0-9.:-]+$", var.pi.bedrock.chat_model_id))
    error_message = "pi.bedrock.chat_model_id must be an Anthropic Claude model ID or cross-Region inference profile ID, e.g. \"global.anthropic.claude-sonnet-4-6\"."
  }
  validation {
    condition     = var.pi.provider != "bedrock" || (var.pi.api_keys.chat_key_secret_arn == null && var.pi.api_keys.embedding_key_secret_arn == null)
    error_message = "pi.api_keys secrets are only used with pi.provider = \"api_keys\"."
  }
  validation {
    condition     = !var.enable_components.pi || var.pi.provider != "api_keys" || (var.pi.api_keys.chat_key_secret_arn != null && var.pi.api_keys.embedding_key_secret_arn != null)
    error_message = "Plane AI with provider API keys (the default) needs both pi.api_keys.chat_key_secret_arn and pi.api_keys.embedding_key_secret_arn."
  }
  validation {
    condition     = contains(["openai", "anthropic"], var.pi.api_keys.chat_provider)
    error_message = "pi.api_keys.chat_provider must be \"openai\" or \"anthropic\"."
  }
  validation {
    condition     = contains([for m in keys(local.pi_embedding_dimensions) : m if !startswith(m, "bedrock/")], var.pi.api_keys.embedding_model)
    error_message = "pi.api_keys.embedding_model must be a Cohere or OpenAI model: ${join(", ", [for m in keys(local.pi_embedding_dimensions) : m if !startswith(m, "bedrock/")])}."
  }
  validation {
    condition     = var.pi.api_keys.chat_key_secret_arn == null || can(regex(local.secret_arn_regex, var.pi.api_keys.chat_key_secret_arn))
    error_message = "pi.api_keys.chat_key_secret_arn must be ${local.secret_arn_format}."
  }
  validation {
    condition     = var.pi.api_keys.embedding_key_secret_arn == null || can(regex(local.secret_arn_regex, var.pi.api_keys.embedding_key_secret_arn))
    error_message = "pi.api_keys.embedding_key_secret_arn must be ${local.secret_arn_format}."
  }
  validation {
    condition     = !(var.pi.api_keys.chat_provider == "openai" && startswith(var.pi.api_keys.embedding_model, "openai/")) || var.pi.api_keys.chat_key_secret_arn == var.pi.api_keys.embedding_key_secret_arn
    error_message = "OpenAI for both chat and embeddings uses one key (OPENAI_API_KEY): set the same secret ARN for both."
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
}

variable "cluster_admin_principal_arns" {
  description = "IAM principal ARNs granted cluster-admin through EKS access entries. The identity running Terraform is added automatically."
  type        = list(string)
  default     = []
  nullable    = false
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
  description = "RDS PostgreSQL Multi-AZ DB cluster (1 writer + 2 readable standbys), sized as today's module."
  type = object({
    engine_version        = optional(string, "15.19")
    instance_class        = optional(string, "db.m6gd.large")
    allocated_storage_gb  = optional(number, 100)
    storage_type          = optional(string, "io1")
    iops                  = optional(number, 1000)
    backup_retention_days = optional(number, 14)
    deletion_protection   = optional(bool, true)
  })
  default  = {}
  nullable = false
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
