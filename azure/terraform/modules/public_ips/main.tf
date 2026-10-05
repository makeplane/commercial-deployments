# Static public IPs for LoadBalancer Services. Creating them here (instead of
# letting AKS allocate one per Service) keeps the address stable across Service
# re-creation and lets DNS be set up before the app is deployed. The Service
# selects one with the annotations
#   service.beta.kubernetes.io/azure-load-balancer-resource-group: <resource group>
#   service.beta.kubernetes.io/azure-pip-name: <name>

# Ingress controller (Traefik) — HTTP/HTTPS for the Plane UI and API.
resource "azurerm_public_ip" "ingress" {
  name                = "${var.name}-ingress-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  domain_name_label   = var.ingress_domain_name_label

  tags = var.tags
}

# Email service — inbound SMTP (25/465/587). Unlike AWS, no NodePort/NLB staging
# is needed: the email Service itself is type LoadBalancer on this IP.
resource "azurerm_public_ip" "email" {
  count = var.email_enabled ? 1 : 0

  name                = "${var.name}-email-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones

  tags = var.tags
}
