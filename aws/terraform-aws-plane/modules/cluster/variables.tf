variable "name" {
  description = "Cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the control plane ENIs and the nodes."
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint."
  type        = list(string)
}

variable "cluster_admin_principal_arns" {
  description = "Extra IAM principals granted cluster-admin."
  type        = list(string)
}

variable "node_group" {
  description = "Managed node group settings."
  type = object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
    disk_size_gb   = number
  })
}

variable "addon_versions" {
  description = "EKS managed add-on versions (null = most recent)."
  type = object({
    vpc_cni                = string
    coredns                = string
    kube_proxy             = string
    eks_pod_identity_agent = string
    aws_ebs_csi_driver     = string
  })
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}
