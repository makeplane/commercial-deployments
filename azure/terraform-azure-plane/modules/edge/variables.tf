variable "name" {
  description = "Name prefix."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group (the cluster's control-plane identity can attach IPs from it)."
  type        = string
}

variable "zones" {
  description = "Availability zones (zone-redundant IPs)."
  type        = list(string)
}

variable "ingress_public_ip" {
  description = "Create Traefik's public IP (path A, internet-facing)."
  type        = bool
}

variable "email_public_ip" {
  description = "Create the email service's public IP."
  type        = bool
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}
