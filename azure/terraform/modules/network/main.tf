locals {
  name_prefix = var.name
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_cidr]

  tags = var.tags
}

# AKS node subnet. Azure CNI Overlay draws pod IPs from a separate overlay CIDR,
# so this subnet only needs room for nodes and internal load balancers.
resource "azurerm_subnet" "aks" {
  name                 = "${local.name_prefix}-aks-nodes"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_cidr]

  # Outbound goes through the NAT gateway below, never the platform default.
  default_outbound_access_enabled = false
}

# PostgreSQL Flexible Server subnet. VNet-integrated servers need a dedicated,
# delegated subnet that holds nothing else.
resource "azurerm_subnet" "postgres" {
  name                 = "${local.name_prefix}-postgres"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.postgres_subnet_cidr]

  default_outbound_access_enabled = false

  delegation {
    name = "postgres-flexible-server"

    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Private endpoints (Redis, Blob storage, optionally Key Vault)
resource "azurerm_subnet" "private_endpoints" {
  name                 = "${local.name_prefix}-private-endpoints"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_endpoints_subnet_cidr]

  default_outbound_access_enabled = false
}

# NAT Gateway — egress for the AKS nodes, with a stable public IP that can be
# allow-listed by external services (Key Vault firewall, SMTP relays, etc.).
resource "azurerm_public_ip" "nat" {
  name                = "${local.name_prefix}-nat-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones

  tags = var.tags
}

resource "azurerm_nat_gateway" "main" {
  name                    = "${local.name_prefix}-nat"
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10

  tags = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "aks" {
  subnet_id      = azurerm_subnet.aks.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}
