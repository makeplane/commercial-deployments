variable "name" {
  description = "Name prefix."
  type        = string
}

variable "project_id" {
  description = "GCP project ID (also the Workload Identity pool <project>.svc.id.goog)."
  type        = string
}

variable "install_traefik" {
  description = "Path A: install Traefik behind a GKE passthrough network load balancer."
  type        = bool
}

variable "allowed_cidrs" {
  description = "Source CIDRs allowed through Traefik's load balancer."
  type        = list(string)
}

variable "load_balancer_scheme" {
  description = "Traefik load balancer scheme: internet-facing or internal."
  type        = string
}

variable "web_address_name" {
  description = "Name of the reserved address for Traefik's load balancer (null in path B)."
  type        = string
}

variable "issue_certificate" {
  description = "Install cert-manager: the module issues the web certificate with Let's Encrypt (HTTP-01)."
  type        = bool
}

variable "certificate_secrets" {
  description = "Customer certificate secrets (web, email) External Secrets may read, as projects/<project>/secrets/<name>."
  type        = list(string)
}

variable "secret_ids" {
  description = "Module Secret Manager secrets External Secrets may read."
  type        = map(string)
}

variable "cluster_ready" {
  description = "Readiness signal from the cluster module (node pool up). Gates every Helm release."
  type        = string
}
