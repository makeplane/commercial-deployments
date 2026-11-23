variable "name" {
  description = "Name prefix."
  type        = string
}

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region (the addresses are regional)."
  type        = string
}

variable "subnet_id" {
  description = "Subnet an internal web address is taken from."
  type        = string
}

variable "install_traefik" {
  description = "Path A: reserve the web address for Traefik's load balancer."
  type        = bool
}

variable "web_scheme" {
  description = "internet-facing (external address) or internal (an address in the subnet)."
  type        = string
}

variable "email_load_balancer" {
  description = "Reserve the email load balancer's address."
  type        = bool
}

variable "labels" {
  description = "Labels."
  type        = map(string)
}
