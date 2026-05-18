variable "cluster_name" {
  description = "EKS cluster name (used for naming and tagging)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the NLB will be created"
  type        = string
}

variable "subnet_ids" {
  description = "Public subnet IDs for the internet-facing NLB (one per AZ)"
  type        = list(string)
}

variable "node_security_group_id" {
  description = "Security group ID of EKS worker nodes — NodePort ingress rules are added here"
  type        = string
}

variable "smtp_node_port" {
  description = "Fixed NodePort for SMTP (port 25)"
  type        = number
  default     = 30025
}

variable "smtps_node_port" {
  description = "Fixed NodePort for SMTPS (port 465)"
  type        = number
  default     = 30465
}

variable "submission_node_port" {
  description = "Fixed NodePort for Submission (port 587)"
  type        = number
  default     = 30587
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
