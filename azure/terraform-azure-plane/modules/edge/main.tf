# Static IPs: known at plan time and survive a Service being recreated.

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
