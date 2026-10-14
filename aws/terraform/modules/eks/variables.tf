variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.28"
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster (private subnets)"
  type        = list(string)
}

variable "node_group_name" {
  description = "Name of the managed node group"
  type        = string
  default     = "default"
}

variable "node_instance_types" {
  description = "List of instance types for the node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of nodes in the node group"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes in the node group"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes in the node group"
  type        = number
  default     = 5
}

variable "node_disk_size" {
  description = "Disk size in GiB for worker nodes"
  type        = number
  default     = 50
}

variable "ssh_key_name" {
  description = "SSH key name for EC2 instances (optional)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
