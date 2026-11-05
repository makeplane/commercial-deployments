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
  description = <<-EOT
    How Plane runs. "eks": EKS with managed data services (RDS, ElastiCache, Amazon MQ, OpenSearch, S3). "docker": one
    EC2 instance running Plane's Docker Compose stack with the bundled data services (see the docker input). Never
    change it on an existing installation: switching modes is a migration.
  EOT
  type        = string
  default     = "eks"
  nullable    = false

  validation {
    condition     = contains(["eks", "docker"], var.deployment_mode)
    error_message = "deployment_mode must be \"eks\" or \"docker\"."
  }
}

variable "plane_version" {
  description = "Plane release to install (EKS: the chart's planeVersion; Docker: the compose assets and image tag). Upgrade by raising it; downgrades aren't supported."
  type        = string
  default     = "v4.0.1"
  nullable    = false

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+[0-9A-Za-z.-]*$", var.plane_version))
    error_message = "plane_version must be a release such as v4.0.1."
  }
}

variable "chart_version" {
  description = "EKS mode: plane-enterprise Helm chart version. 3.11.3 or later (configurable email Service)."
  type        = string
  default     = "3.11.3"
  nullable    = false
}

variable "chart_repository" {
  description = "EKS mode: Helm repository of the plane-enterprise chart. Override only to test a preview build."
  type        = string
  default     = "https://helm.plane.so/"
  nullable    = false
}

variable "chart_name" {
  description = "EKS mode: chart name in chart_repository (preview builds are named <commit>-plane-enterprise)."
  type        = string
  default     = "plane-enterprise"
  nullable    = false
}

variable "acme_email" {
  description = <<-EOT
    Path A (ingress.mode = "automated"), variant A.1: the Let's Encrypt account email. The web certificate is issued
    with HTTP-01 (EKS: cert-manager through Traefik; Docker: the stack's Caddy proxy): Plane must be public on port 80,
    and the certificate is issued once your DNS record for domain points at Plane (dns_records). Leave null for your
    own certificates (ingress.tls_certificate_secret_arn, variant A.2) or for path B.
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
  description = "Optional Plane workloads. pi (Plane AI) needs AI provider keys, which are set in the admin UI in this release. drawio is EKS only (the Compose stack has no drawio service)."
  type = object({
    silo   = optional(bool, true)
    drawio = optional(bool, true)
    pi     = optional(bool, false)
  })
  default  = {}
  nullable = false
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
    How traffic reaches Plane. mode = "automated" (path A): EKS installs Traefik behind an NLB, Plane's routes and the
    certificates; Docker serves Plane from the stack's Caddy proxy on the instance (an Elastic IP when internet-facing).
    Certificates: Let's Encrypt via acme_email, or your own via tls_certificate_secret_arn. mode = "none" (path B):
    EKS installs no ingress controller or routes; Docker puts the instance in a private subnet serving plain HTTP on
    port 80 for your own load balancer. Default: "none" in EKS mode, "automated" in Docker mode. The module configures
    no DNS: the records are yours in both paths (see the dns_records output). Path A only: allowed_cidrs (who can
    reach Plane), scheme (internet-facing or internal) and tls_certificate_secret_arn (a Secrets Manager secret with
    JSON keys "tls.crt" and "tls.key", full chain, encrypted with the default aws/secretsmanager key or this module's
    KMS key).
  EOT
  type = object({
    mode                       = optional(string)
    allowed_cidrs              = optional(list(string), ["0.0.0.0/0"])
    scheme                     = optional(string, "internet-facing")
    tls_certificate_secret_arn = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["none", "automated"], coalesce(var.ingress.mode, "none"))
    error_message = "ingress.mode must be \"automated\" (path A) or \"none\" (path B)."
  }
  validation {
    condition     = contains(["internet-facing", "internal"], var.ingress.scheme)
    error_message = "ingress.scheme must be \"internet-facing\" or \"internal\"."
  }
  validation {
    condition     = coalesce(var.ingress.mode, var.deployment_mode == "docker" ? "automated" : "none") != "automated" || ((var.acme_email != null) != (var.ingress.tls_certificate_secret_arn != null))
    error_message = "Path A (ingress.mode = \"automated\") needs exactly one web certificate source: acme_email (Let's Encrypt) or ingress.tls_certificate_secret_arn (your own certificate)."
  }
  validation {
    condition     = !(coalesce(var.ingress.mode, var.deployment_mode == "docker" ? "automated" : "none") == "automated" && var.acme_email != null) || (contains(var.ingress.allowed_cidrs, "0.0.0.0/0") && var.ingress.scheme == "internet-facing")
    error_message = "Let's Encrypt (acme_email) uses HTTP-01, which needs Plane reachable from the internet on port 80: ingress.allowed_cidrs must include 0.0.0.0/0 and ingress.scheme must be internet-facing. Use your own certificate (ingress.tls_certificate_secret_arn) to restrict access."
  }
}

variable "tls_secret_name" {
  description = "EKS mode, path A: name of the Kubernetes TLS Secret in the plane namespace that Traefik serves. Written by cert-manager (acme_email) or by External Secrets from ingress.tls_certificate_secret_arn."
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
  description = "Availability zones to use. The RDS Multi-AZ DB cluster needs at least 3. Docker mode uses the first one for the instance."
  type        = number
  default     = 3
  nullable    = false

  validation {
    condition     = var.az_count >= 3
    error_message = "az_count must be at least 3 (RDS Multi-AZ DB clusters need three AZs)."
  }
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cheaper, as today's module) instead of one per AZ. Docker mode, path A internet-facing, has no NAT gateway (the instance uses its Elastic IP)."
  type        = bool
  default     = true
  nullable    = false
}

################################################################################
# EKS mode
################################################################################

variable "kubernetes_version" {
  description = "EKS mode: EKS Kubernetes version."
  type        = string
  default     = "1.36"
  nullable    = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "EKS mode: CIDRs allowed to reach the public EKS API endpoint. The private endpoint is always on. Restrict this to your office, VPN or CI ranges."
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = false
}

variable "cluster_admin_principal_arns" {
  description = "EKS mode: IAM principal ARNs granted cluster-admin through EKS access entries. The identity running Terraform is added automatically."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "node_group" {
  description = <<-EOT
    EKS mode: the managed node group: starts at desired_size nodes and can range from min_size to max_size (2 to 4 by default, as
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
  description = "EKS mode: EKS managed add-on versions. null for an add-on means the most recent version for kubernetes_version."
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
  description = "EKS mode: seconds to wait for the Plane Helm release. A fresh install's migrations take about 20 minutes."
  type        = number
  default     = 3600
  nullable    = false
}

variable "plane_values" {
  description = "EKS mode: extra plane-enterprise chart values (YAML string), merged last. Never put secrets here: they end up in Terraform state and the Helm release."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.deployment_mode != "docker" || var.plane_values == ""
    error_message = "plane_values are Helm chart values (EKS mode); in Docker mode use docker.extra_env."
  }
}

################################################################################
# Data services (EKS mode)
################################################################################

variable "postgres" {
  description = "EKS mode: RDS PostgreSQL Multi-AZ DB cluster (1 writer + 2 readable standbys), sized as today's module."
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
  description = "EKS mode: ElastiCache Valkey with TLS, an AUTH token and at-rest encryption, as Plane's own production cache."
  type = object({
    engine_version = optional(string, "8.2")
    node_type      = optional(string, "cache.t3.medium")
    replicas       = optional(number, 0)
  })
  default  = {}
  nullable = false
}

variable "rabbitmq" {
  description = "EKS mode: Amazon MQ for RabbitMQ."
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
    EKS mode: Amazon OpenSearch Service for Plane's search, on by default as in today's deployments: a private domain in the VPC
    (HTTPS only, KMS, node-to-node encryption), reached by Plane with its Pod Identity role (SigV4, no passwords). The
    chart's Job creates the search indexes after every install and upgrade. enabled = false: Plane runs with search
    indexing off. Docker mode has no search service (search indexing off).
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
    Docker mode has no load balancer: load_balancer = true opens the three ports on the instance (path A
    internet-facing: to everyone, MX record pointing at domain; otherwise only from where Plane is reachable).
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
}

variable "bucket_force_destroy" {
  description = "Allow terraform destroy to delete the uploads bucket (EKS) or the backups bucket (Docker) even when it holds objects."
  type        = bool
  default     = false
  nullable    = false
}

################################################################################
# Docker mode
################################################################################

variable "docker" {
  description = <<-EOT
    Docker mode (deployment_mode = "docker"): one EC2 instance (Ubuntu 24.04, x86_64) runs Plane's published Docker
    Compose stack with the bundled Postgres, Valkey, RabbitMQ and MinIO; data on a separate encrypted EBS volume
    (data_volume_gb, mounted at /opt/plane). SSM installs Docker (docker_version, compose_version: a version or prefix
    in Docker's apt repository), fetches <compose_assets_url>/<plane_version>/docker-compose.yml and variables.env
    (https:// or s3://; compose_assets_sha256 = { "docker-compose.yml" = "<sha256>", "variables.env" = "<sha256>" }
    to pin them), writes plane.env with the generated secrets and starts the stack; the apply waits up to
    setup_timeout_minutes. extra_env: more plane.env settings (no secrets: they're stored in the SSM document; not the
    keys the module sets). Backups: daily EBS snapshots and a nightly pg_dump + MinIO mirror to S3 at backup_time
    (UTC, HH:MM), kept backup_retention_days. data_volume_snapshot_id restores the data volume from a snapshot.
    Ignored in EKS mode.
  EOT
  type = object({
    instance_type           = optional(string, "m7a.xlarge")
    data_services           = optional(string, "bundled")
    root_volume_gb          = optional(number, 50)
    data_volume_gb          = optional(number, 100)
    data_volume_snapshot_id = optional(string)
    compose_assets_url      = optional(string, "https://prime.plane.so/deployment/assets")
    compose_assets_sha256   = optional(map(string), {})
    docker_version          = optional(string, "29.9.2")
    compose_version         = optional(string, "5.6.1")
    extra_env               = optional(map(string), {})
    backup_time             = optional(string, "03:00")
    backup_retention_days   = optional(number, 14)
    setup_timeout_minutes   = optional(number, 60)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !can(regex("^t[0-9]", var.docker.instance_type))
    error_message = "docker.instance_type must not be a burstable (t*) type: migrations and imports need sustained CPU."
  }
  validation {
    condition     = var.docker.data_services == "bundled"
    error_message = "docker.data_services must be \"bundled\" (managed data services in Docker mode come later)."
  }
  validation {
    condition     = var.docker.root_volume_gb >= 30 && var.docker.data_volume_gb >= 50
    error_message = "docker.root_volume_gb must be at least 30 and docker.data_volume_gb at least 50."
  }
  validation {
    condition     = var.docker.data_volume_snapshot_id == null || can(regex("^snap-[0-9a-f]+$", coalesce(var.docker.data_volume_snapshot_id, "-")))
    error_message = "docker.data_volume_snapshot_id must be an EBS snapshot ID (snap-...)."
  }
  validation {
    condition     = can(regex("^(https|s3)://[^\\s'\"]+$", var.docker.compose_assets_url))
    error_message = "docker.compose_assets_url must be an https:// or s3:// URL."
  }
  validation {
    condition = alltrue([
      for k, v in var.docker.compose_assets_sha256 : contains(["docker-compose.yml", "variables.env"], k) && can(regex("^[0-9a-f]{64}$", v))
    ])
    error_message = "docker.compose_assets_sha256 keys are \"docker-compose.yml\" and \"variables.env\"; values are lowercase hex SHA-256 digests."
  }
  validation {
    condition     = alltrue([for v in [var.docker.docker_version, var.docker.compose_version] : can(regex("^[0-9]+(\\.[0-9]+){0,2}$", v))])
    error_message = "docker.docker_version and docker.compose_version must be versions or prefixes such as 29.9.2 or 29.9."
  }
  validation {
    condition = alltrue([
      for k, v in var.docker.extra_env : can(regex("^[A-Z][A-Z0-9_]*$", k)) && !strcontains(v, "'") && !strcontains(v, "\n") && !contains([
        "INSTALL_DIR", "DOMAIN_NAME", "APP_RELEASE_VERSION", "IS_AIRGAPPED", "APP_PROTOCOL", "WEB_URL", "CORS_ALLOWED_ORIGINS",
        "SITE_ADDRESS", "CERT_EMAIL", "CERT_ACME_CA", "TRUSTED_PROXIES", "OPENSEARCH_ENABLED", "POSTGRES_USER", "POSTGRES_DB",
        "RABBITMQ_USER", "RABBITMQ_DEFAULT_USER", "RABBITMQ_VHOST", "RABBITMQ_DEFAULT_VHOST", "SILO_REPLICAS", "PI_API_REPLICAS",
        "PI_BEAT_REPLICAS", "PI_WORKER_REPLICAS", "PI_MIGRATOR_REPLICAS", "EMAIL_REPLICAS", "LISTEN_SMTP_PORT_25",
        "LISTEN_SMTP_PORT_465", "LISTEN_SMTP_PORT_587", "SMTP_DOMAIN", "INTAKE_EMAIL_DOMAIN", "TLS_CERT_PATH", "TLS_PRIV_KEY_PATH",
        "SECRET_KEY", "AES_SECRET_KEY", "AES_SALT", "SILO_HMAC_SECRET_KEY", "LIVE_SERVER_SECRET_KEY", "PI_INTERNAL_SECRET",
        "CURSOR_WEBHOOK_SECRET", "WEBHOOK_SECRET", "ARGUS_FINGERPRINT_SECRET", "ARGUS_INTERNAL_SECRET", "MACHINE_SIGNATURE",
        "POSTGRES_PASSWORD", "DATABASE_URL", "FOLLOWER_POSTGRES_URI", "PLANE_PI_DATABASE_URL", "RABBITMQ_PASSWORD",
        "RABBITMQ_DEFAULT_PASS", "AMQP_URL", "MINIO_ROOT_USER", "MINIO_ROOT_PASSWORD", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY",
      ], k)
    ])
    error_message = "docker.extra_env: keys are uppercase env names, values have no quote (') or newline, and the keys the module sets (domain, version, ports, replicas, secrets, AES_SALT) can't be overridden."
  }
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.docker.backup_time))
    error_message = "docker.backup_time must be HH:MM (UTC), e.g. 03:00."
  }
  validation {
    condition     = var.docker.backup_retention_days >= 1 && var.docker.backup_retention_days <= 365
    error_message = "docker.backup_retention_days must be 1-365."
  }
  validation {
    condition     = var.docker.setup_timeout_minutes >= 20 && var.docker.setup_timeout_minutes <= 240
    error_message = "docker.setup_timeout_minutes must be 20-240."
  }
}
