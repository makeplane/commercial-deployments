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
  description = "Public subnets for the NLB."
  type        = list(string)
}

variable "allowed_cidrs" {
  description = "Source CIDRs allowed through the NLB."
  type        = list(string)
}

variable "route53_zone_id" {
  description = "Route 53 zone for DNS-01 (null = HTTP-01)."
  type        = string
}

variable "email_enabled" {
  description = "Plane's email service is on: its LoadBalancer Service gets an internet-facing NLB."
  type        = bool
}

variable "issue_certificate" {
  description = "Install cert-manager: the module issues Plane's certificate."
  type        = bool
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
