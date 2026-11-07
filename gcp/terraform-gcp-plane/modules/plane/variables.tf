variable "name" {
  description = "Name prefix."
  type        = string
}

variable "project_id" {
  description = "GCP project ID (Secret Manager, GCS and the Workload Identity pool)."
  type        = string
}

variable "domain" {
  description = "Plane FQDN."
  type        = string
}

variable "plane_version" {
  description = "Plane release (chart planeVersion)."
  type        = string
}

variable "chart_version" {
  description = "plane-enterprise chart version."
  type        = string
}

variable "pods_cidr" {
  description = "GKE pods range (trusted proxy range for the api: Traefik reaches it from a pod IP)."
  type        = string
}

variable "enable_components" {
  description = "Optional Plane workloads."
  type = object({
    silo   = bool
    drawio = bool
    pi     = bool
  })
}

variable "tls_secret_name" {
  description = "TLS Secret Traefik serves."
  type        = string
}

variable "ingress_enabled" {
  description = "Path A: render Plane's Traefik routes (and issue or sync the web certificate)."
  type        = bool
}

variable "tls_certificate_secret" {
  description = "Path A: customer web certificate in Secret Manager (null = Let's Encrypt, if acme_email)."
  type        = string
}

variable "email" {
  description = "Plane's email service: on, the domain that receives mail, whether it gets its own load balancer, and its certificate."
  type = object({
    enabled            = bool
    smtp_domain        = string
    load_balancer      = bool
    certificate_secret = string
  })
}

variable "email_address_name" {
  description = "Name of the reserved address for the email load balancer (null without one)."
  type        = string
}

variable "chart_repository" {
  description = "Helm repository of the plane-enterprise chart."
  type        = string
}

variable "chart_name" {
  description = "Chart name in that repository."
  type        = string
}

variable "acme_email" {
  description = "Let's Encrypt account email (null = no Let's Encrypt)."
  type        = string
}

variable "acme_server" {
  description = "ACME directory URL."
  type        = string
}

variable "use_storage_proxy" {
  description = "Attachments, editor images and similar go through the api instead of signed URLs (silo, live and pi do not read it)."
  type        = bool
}

variable "rabbitmq" {
  description = "In-cluster RabbitMQ settings."
  type = object({
    volume_size_gb = number
  })
}

variable "opensearch" {
  description = "In-cluster OpenSearch settings."
  type = object({
    enabled        = bool
    volume_size_gb = number
    index_prefix   = string
  })
}

variable "pi" {
  description = "Plane AI's embedding model, its dimension (the search indexes use it with pi on or off) and api_key_secrets: env var pi reads => Secret Manager secret (projects/<project>/secrets/<name>)."
  type = object({
    embedding_model     = string
    embedding_dimension = number
    api_key_secrets     = map(string)
  })
}

variable "helm_timeout" {
  description = "Seconds to wait for the release."
  type        = number
}

variable "plane_values" {
  description = "Extra chart values (YAML), merged last."
  type        = string
}

variable "data" {
  description = "Data-layer endpoints and secret names (modules/data plane_inputs)."
  type = object({
    bucket_name        = string
    postgres_host      = string
    postgres_port      = number
    postgres_db        = string
    redis_host         = string
    redis_port         = number
    redis_ca           = string
    opensearch_enabled = bool
    secret_names       = map(string)
    app_key_names      = list(string)
  })
}

variable "addons_ready" {
  description = "Readiness signal from the addons module. Gates the Plane release (and orders its destroy first)."
  type        = string
}
