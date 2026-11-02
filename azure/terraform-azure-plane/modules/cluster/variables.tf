variable "name" {
  description = "Cluster name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group."
  type        = string
}

variable "resource_group_id" {
  description = "Resource group ID (scope of the control plane's Network Contributor role)."
  type        = string
}

variable "subnet_id" {
  description = "AKS node subnet (NAT gateway attached)."
  type        = string
}

variable "zones" {
  description = "Availability zones for the nodes."
  type        = list(string)
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version."
  type        = string
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the API server (empty = open)."
  type        = list(string)
}

variable "tenant_id" {
  description = "Entra ID tenant the cluster authenticates against."
  type        = string
}

variable "deployer_object_id" {
  description = "Object ID of the identity running Terraform (granted cluster admin)."
  type        = string
}

variable "cluster_admin_object_ids" {
  description = "Extra Entra ID object IDs granted cluster admin."
  type        = list(string)
}

variable "node_pool" {
  description = "Node pool settings."
  type = object({
    vm_size         = string
    min_count       = number
    max_count       = number
    node_count      = number
    os_disk_size_gb = number
    sku_tier        = string
  })
}

variable "pod_cidr" {
  description = "Overlay CIDR for pod IPs."
  type        = string
}

variable "service_cidr" {
  description = "CIDR for Service IPs."
  type        = string
}

variable "dns_service_ip" {
  description = "Cluster DNS Service IP (inside service_cidr)."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}
