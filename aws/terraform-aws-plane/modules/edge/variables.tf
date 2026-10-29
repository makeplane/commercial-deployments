variable "name" {
  description = "Name prefix."
  type        = string
}

variable "domain" {
  description = "Plane FQDN."
  type        = string
}

variable "ip_count" {
  description = "Number of EIPs: one per public subnet the NLB spans."
  type        = number
}

variable "route53_zone_id" {
  description = "Route 53 zone for the A record (null = DNS is managed outside the module)."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}
