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
  description = "Public subnets for the NLB, one per EIP."
  type        = list(string)
}

variable "eip_allocation_ids" {
  description = "EIP allocation IDs attached to the NLB."
  type        = list(string)
}

variable "allowed_cidrs" {
  description = "Source CIDRs allowed through the NLB."
  type        = list(string)
}

variable "route53_zone_id" {
  description = "Route 53 zone for DNS-01 (null = no cert-manager)."
  type        = string
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
