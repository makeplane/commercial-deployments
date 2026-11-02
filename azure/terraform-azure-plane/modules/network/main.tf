# VNet with three subnets and a NAT gateway: the nodes' only way out. Adapted from azure/terraform/modules/network.

resource "azurerm_virtual_network" "this" {
  name                = "${var.name}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_cidr]

  tags = var.tags
}

# AKS nodes and internal load balancers. Azure CNI Overlay gives pods addresses from a separate
# overlay range, so this subnet only needs room for nodes.
resource "azurerm_subnet" "aks" {
  # checkov:skip=CKV2_AZURE_31:AKS manages the network security group of its nodes (and writes the loadBalancerSourceRanges rules there).
  name                 = "${var.name}-aks-nodes"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.aks_subnet_cidr]

  # Outbound only through the NAT gateway below, never the platform default.
  default_outbound_access_enabled = false
}

# PostgreSQL Flexible Server: VNet-integrated servers need a dedicated, delegated subnet.
resource "azurerm_subnet" "postgres" {
  # checkov:skip=CKV2_AZURE_31:Delegated to PostgreSQL Flexible Server, which holds nothing else; the server isn't reachable from outside the VNet.
  name                 = "${var.name}-postgres"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
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

# Private endpoints: Redis, Blob storage and (optionally) Key Vault.
resource "azurerm_subnet" "private_endpoints" {
  # checkov:skip=CKV2_AZURE_31:Holds only private endpoints, reachable from inside the VNet.
  name                 = "${var.name}-private-endpoints"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.private_endpoints_subnet_cidr]

  default_outbound_access_enabled = false
}

# Egress for the nodes on a stable address that can be allow-listed (Key Vault firewall, SMTP
# relays, identity providers).
resource "azurerm_public_ip" "nat" {
  name                = "${var.name}-nat-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones

  tags = var.tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "${var.name}-nat"
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10

  tags = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "aks" {
  subnet_id      = azurerm_subnet.aks.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}
