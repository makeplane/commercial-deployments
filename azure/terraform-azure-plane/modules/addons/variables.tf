variable "name" {
  description = "Name prefix."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group (identities; Traefik's public IP)."
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant."
  type        = string
}

variable "oidc_issuer_url" {
  description = "The cluster's OIDC issuer (Workload Identity)."
  type        = string
}

variable "install_traefik" {
  description = "Path A: install Traefik behind an Azure load balancer."
  type        = bool
}

variable "allowed_cidrs" {
  description = "Source CIDRs allowed through Traefik's load balancer."
  type        = list(string)
}

variable "load_balancer_scheme" {
  description = "Traefik load balancer: internet-facing (static public IP) or internal (fixed private IP)."
  type        = string
}

variable "ingress_public_ip_name" {
  description = "Name of Traefik's static public IP (internet-facing; null otherwise)."
  type        = string
}

variable "internal_ingress_ip" {
  description = "Traefik's private IP in the AKS subnet (internal)."
  type        = string
}

variable "issue_certificate" {
  description = "Install cert-manager: the module issues the web certificate with Let's Encrypt (HTTP-01)."
  type        = bool
}

variable "key_vault_id" {
  description = "The module's Key Vault (External Secrets reads it)."
  type        = string
}

variable "customer_secret_scopes" {
  description = "Key Vault secret IDs of the customer's certificates (web, email) and Plane AI keys External Secrets may read."
  type        = list(string)
}

variable "cluster_ready" {
  description = "Readiness signal from the cluster module (node pool up, admin roles propagated). Gates every Helm release."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}
