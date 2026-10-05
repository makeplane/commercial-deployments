variable "name" {
  description = "Name prefix for the public IPs"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the public IPs"
  type        = string
}

variable "zones" {
  description = "Availability zones (zone-redundant when all are listed)"
  type        = list(string)
}

variable "ingress_domain_name_label" {
  description = "Optional DNS label: <label>.<region>.cloudapp.azure.com points at the ingress IP"
  type        = string
  default     = null
}

variable "email_enabled" {
  description = "Create a public IP for the email service"
  type        = bool
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
