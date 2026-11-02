variable "install_traefik" {
  description = "Path A: the module installs Traefik (and its NLB)."
  type        = bool
}

variable "load_balancer_name" {
  description = "Name of the NLB the AWS Load Balancer Controller creates for Traefik."
  type        = string
}

variable "addons_ready" {
  description = "Available once the add-ons (Traefik and its NLB) are installed."
  type        = string
}
