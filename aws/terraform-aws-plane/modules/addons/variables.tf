variable "name" {
  description = "Name prefix."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR (trusted source of proxy-protocol headers)."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for an internet-facing NLB."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for an internal NLB."
  type        = list(string)
}

variable "install_traefik" {
  description = "Path A: install Traefik behind an NLB."
  type        = bool
}

variable "allowed_cidrs" {
  description = "Source CIDRs allowed through the Traefik NLB."
  type        = list(string)
}

variable "load_balancer_scheme" {
  description = "Traefik NLB scheme: internet-facing or internal."
  type        = string
}

variable "issue_certificate" {
  description = "Install cert-manager: the module issues the web certificate with Let's Encrypt (HTTP-01)."
  type        = bool
}

variable "certificate_secret_arns" {
  description = "Customer certificate secrets (web, email) External Secrets may read."
  type        = list(string)
}

variable "secret_arns" {
  description = "Secrets Manager ARNs External Secrets may read."
  type        = map(string)
}

variable "kms_key_arn" {
  description = "KMS key encrypting those secrets."
  type        = string
}

variable "cluster_ready" {
  description = "Readiness signal from the cluster module (node group up). Gates every Helm release."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}
