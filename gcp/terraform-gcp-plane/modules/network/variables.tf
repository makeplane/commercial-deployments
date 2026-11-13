variable "name" {
  description = "Name prefix."
  type        = string
}

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
}

variable "enable_apis" {
  description = "Enable the project APIs the module needs."
  type        = bool
}

variable "network" {
  description = "Address ranges: subnet, pods, services and private services access."
  type = object({
    subnet_cidr          = string
    services_cidr        = string
    private_service_cidr = string
    pods_cidr            = string
  })
}
