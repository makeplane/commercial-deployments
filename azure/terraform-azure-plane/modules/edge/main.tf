# Static public IPs for the module's load balancers, created before the cluster: the addresses are
# known at plan time, so dns_records is complete before Helm runs, and they survive a Service being
# recreated. The module creates no DNS records. A LoadBalancer Service takes one with the annotations
#   service.beta.kubernetes.io/azure-pip-name: <name>
#   service.beta.kubernetes.io/azure-load-balancer-resource-group: <resource group>
# (the cluster's control-plane identity has Network Contributor on the resource group).

# Path A, internet-facing: Traefik (HTTP/HTTPS).
resource "azurerm_public_ip" "ingress" {
  count = var.ingress_public_ip ? 1 : 0

  name                = "${var.name}-ingress-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones

  tags = var.tags
}

# Email service: inbound SMTP (25/465/587).
resource "azurerm_public_ip" "email" {
  count = var.email_public_ip ? 1 : 0

  name                = "${var.name}-email-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones

  tags = var.tags
}
