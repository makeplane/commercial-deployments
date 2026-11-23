variable "name" {
  description = "Name prefix (also the cluster name)."
  type        = string
}

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region (the cluster is regional)."
  type        = string
}

variable "zones" {
  description = "Node zones; empty lets GKE pick."
  type        = list(string)
}

variable "network_id" {
  description = "VPC network ID."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the nodes."
  type        = string
}

variable "pods_range_name" {
  description = "Secondary range for pods."
  type        = string
}

variable "services_range_name" {
  description = "Secondary range for services."
  type        = string
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the public API endpoint."
  type        = list(string)
}

variable "cluster_admin_members" {
  description = "IAM members granted roles/container.admin."
  type        = list(string)
}

variable "release_channel" {
  description = "GKE release channel."
  type        = string
}

variable "node_pool" {
  description = "Node pool settings."
  type = object({
    machine_type = string
    min_per_zone = number
    max_per_zone = number
    disk_size_gb = number
    disk_type    = string
    spot         = bool
  })
}

variable "labels" {
  description = "Labels."
  type        = map(string)
}
