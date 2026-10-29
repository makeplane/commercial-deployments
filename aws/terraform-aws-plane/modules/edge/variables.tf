variable "domain" {
  description = "Plane FQDN."
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 zone for the alias record (null = DNS is managed outside the module)."
  type        = string
}

variable "load_balancer_name" {
  description = "Name of the NLB the AWS Load Balancer Controller creates for Traefik."
  type        = string
}

variable "addons_ready" {
  description = "Available once the add-ons (Traefik and its NLB) are installed."
  type        = string
}
