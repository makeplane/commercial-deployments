# Every module input, same names and types. Unset (null) means the module default: set only what you need in
# terraform.tfvars (see terraform.tfvars.example for every default). Generated to match the module; CI checks the names.

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Prefix for every resource the module creates. Lowercase letters, digits and hyphens, at most 20 characters."
  type        = string

}

variable "domain" {
  description = "FQDN Plane is served on. It is also the licence domain and part of the instance identity, so it must never change after install."
  type        = string

}

variable "deployment_mode" {
  description = <<-EOT
    How Plane runs. "eks": EKS with managed data services (RDS, ElastiCache, Amazon MQ, OpenSearch, S3). "docker": one
    EC2 instance running Plane's Docker Compose stack with the bundled data services (see the docker input). Never
    change it on an existing installation: switching modes is a migration.
  EOT
  type        = string
  default     = null
}

variable "plane_version" {
  description = "Plane release to install (EKS: the chart's planeVersion; Docker: the compose assets and image tag). Upgrade by raising it; downgrades aren't supported."
  type        = string
  default     = null
}

variable "chart_version" {
  description = "EKS mode: plane-enterprise Helm chart version. 3.11.3 or later (configurable email Service)."
  type        = string
  default     = null
}

variable "chart_repository" {
  description = "EKS mode: Helm repository of the plane-enterprise chart. Override only to test a preview build."
  type        = string
  default     = null
}

variable "chart_name" {
  description = "EKS mode: chart name in chart_repository (preview builds are named <commit>-plane-enterprise)."
  type        = string
  default     = null
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
  default     = null
}

variable "enable_components" {
  description = "Optional Plane workloads. pi (Plane AI) needs AI provider keys, which are set in the admin UI in this release. drawio is EKS only (the Compose stack has no drawio service)."
  type = object({
    silo   = optional(bool)
    drawio = optional(bool)
    pi     = optional(bool)
  })
  default = null
}

variable "tags" {
  description = "Tags applied to every AWS resource."
  type        = map(string)
  default     = null
}

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
    allowed_cidrs              = optional(list(string))
    scheme                     = optional(string)
    tls_certificate_secret_arn = optional(string)
  })
  default = null
}

variable "tls_secret_name" {
  description = "EKS mode, path A: name of the Kubernetes TLS Secret in the plane namespace that Traefik serves. Written by cert-manager (acme_email) or by External Secrets from ingress.tls_certificate_secret_arn."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "CIDR of the VPC the module creates. Must not overlap networks you will peer or VPN with. The default avoids 10.0.0.0/16, the default of most VPC tooling and of the older aws/terraform module."
  type        = string
  default     = null
}

variable "az_count" {
  description = "Availability zones to use. The RDS Multi-AZ DB cluster needs at least 3. Docker mode uses the first one for the instance."
  type        = number
  default     = null
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cheaper, as today's module) instead of one per AZ. Docker mode, path A internet-facing, has no NAT gateway (the instance uses its Elastic IP)."
  type        = bool
  default     = null
}

variable "kubernetes_version" {
  description = "EKS mode: EKS Kubernetes version."
  type        = string
  default     = null
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "EKS mode: CIDRs allowed to reach the public EKS API endpoint. The private endpoint is always on. Restrict this to your office, VPN or CI ranges."
  type        = list(string)
  default     = null
}

variable "cluster_admin_principal_arns" {
  description = "EKS mode: IAM principal ARNs granted cluster-admin through EKS access entries. The identity running Terraform is added automatically."
  type        = list(string)
  default     = null
}

variable "node_group" {
  description = <<-EOT
    EKS mode: the managed node group: starts at desired_size nodes and can range from min_size to max_size (2 to 4 by default, as
    today). No node autoscaler in this release, so it stays at desired_size until scaled by hand (aws eks
    update-nodegroup-config --scaling-config desiredSize=N) or by an autoscaler added later. Terraform sets desired_size
    only at creation and leaves later changes alone.
  EOT
  type = object({
    instance_types = optional(list(string))
    min_size       = optional(number)
    max_size       = optional(number)
    desired_size   = optional(number)
    disk_size_gb   = optional(number)
  })
  default = null
}

variable "addon_versions" {
  description = "EKS mode: EKS managed add-on versions. null for an add-on means the most recent version for kubernetes_version."
  type = object({
    vpc_cni                = optional(string)
    coredns                = optional(string)
    kube_proxy             = optional(string)
    eks_pod_identity_agent = optional(string)
    aws_ebs_csi_driver     = optional(string)
  })
  default = null
}

variable "helm_timeout" {
  description = "EKS mode: seconds to wait for the Plane Helm release. A fresh install's migrations take about 20 minutes."
  type        = number
  default     = null
}

variable "plane_values" {
  description = "EKS mode: extra plane-enterprise chart values (YAML string), merged last. Never put secrets here: they end up in Terraform state and the Helm release."
  type        = string
  default     = null
}

variable "postgres" {
  description = "EKS mode: RDS PostgreSQL Multi-AZ DB cluster (1 writer + 2 readable standbys), sized as today's module."
  type = object({
    engine_version        = optional(string)
    instance_class        = optional(string)
    allocated_storage_gb  = optional(number)
    storage_type          = optional(string)
    iops                  = optional(number)
    backup_retention_days = optional(number)
    deletion_protection   = optional(bool)
  })
  default = null
}

variable "redis" {
  description = "EKS mode: ElastiCache Valkey with TLS, an AUTH token and at-rest encryption, as Plane's own production cache."
  type = object({
    engine_version = optional(string)
    node_type      = optional(string)
    replicas       = optional(number)
  })
  default = null
}

variable "rabbitmq" {
  description = "EKS mode: Amazon MQ for RabbitMQ."
  type = object({
    engine_version  = optional(string)
    instance_type   = optional(string)
    deployment_mode = optional(string)
  })
  default = null
}

variable "opensearch" {
  description = <<-EOT
    EKS mode: Amazon OpenSearch Service for Plane's search, on by default as in today's deployments: a private domain in the VPC
    (HTTPS only, KMS, node-to-node encryption), reached by Plane with its Pod Identity role (SigV4, no passwords). The
    chart's Job creates the search indexes after every install and upgrade. enabled = false: Plane runs with search
    indexing off. Docker mode has no search service (search indexing off).
  EOT
  type = object({
    enabled        = optional(bool)
    engine_version = optional(string)
    instance_type  = optional(string)
    instance_count = optional(number)
    volume_size_gb = optional(number)
    # Index names are "<index_prefix>_<name>", as today's deployments ("plane"). Changing it on a running install
    # needs the indexes created again and re-filled (manage_search_index index create + document index).
    index_prefix = optional(string)
  })
  default = null
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
    enabled                = optional(bool)
    smtp_domain            = optional(string)
    load_balancer          = optional(bool)
    certificate_secret_arn = optional(string)
  })
  default = null
}

variable "bucket_force_destroy" {
  description = "Allow terraform destroy to delete the uploads bucket (EKS) or the backups bucket (Docker) even when it holds objects."
  type        = bool
  default     = null
}

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
    instance_type           = optional(string)
    data_services           = optional(string)
    root_volume_gb          = optional(number)
    data_volume_gb          = optional(number)
    data_volume_snapshot_id = optional(string)
    compose_assets_url      = optional(string)
    compose_assets_sha256   = optional(map(string))
    docker_version          = optional(string)
    compose_version         = optional(string)
    extra_env               = optional(map(string))
    backup_time             = optional(string)
    backup_retention_days   = optional(number)
    setup_timeout_minutes   = optional(number)
  })
  default = null
}
