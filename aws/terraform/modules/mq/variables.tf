variable "cluster_name" {
  description = "Cluster name for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the broker (private subnets)"
  type        = list(string)
}

variable "vpc_cidr" {
  description = "VPC CIDR block allowed to access MQ"
  type        = string
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to access MQ (e.g., EKS node SG)"
  type        = list(string)
  default     = []
}

variable "mq_username" {
  description = "RabbitMQ username"
  type        = string
}

variable "mq_password" {
  description = "RabbitMQ password"
  type        = string
  sensitive   = true
}

variable "engine_version" {
  description = "RabbitMQ engine version (valid: 4.2, 3.13)"
  type        = string
  default     = "4.2"
}

variable "instance_type" {
  description = "Broker instance type"
  type        = string
  default     = "mq.t3.micro"
}

variable "deployment_mode" {
  description = "Deployment mode: SINGLE_INSTANCE, ACTIVE_STANDBY_MULTI_AZ, or CLUSTER_MULTI_AZ"
  type        = string
  default     = "SINGLE_INSTANCE"
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
