variable "cluster_name" {
  description = "Name of the EKS cluster (used for IAM role and policy names)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS cluster OIDC provider (for IRSA)"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS cluster OIDC issuer (e.g. https://oidc.eks.region.amazonaws.com/id/ID)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to IAM resources"
  type        = map(string)
  default     = {}
}
