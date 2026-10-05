# Azure Managed Redis. The successor to Azure Cache for Redis, which is being
# retired; it listens with TLS only, on port 10000.
resource "azurerm_managed_redis" "main" {
  name                      = "${var.name}-redis"
  location                  = var.location
  resource_group_name       = var.resource_group_name
  sku_name                  = var.sku_name
  high_availability_enabled = var.high_availability_enabled
  public_network_access     = "Disabled"

  default_database {
    # Plane authenticates with a password (REDIS_PASSWORD), i.e. an access key.
    access_keys_authentication_enabled = true
    client_protocol                    = "Encrypted"
    clustering_policy                  = var.clustering_policy
  }

  tags = var.tags
}

resource "azurerm_private_dns_zone" "redis" {
  name                = "privatelink.redis.azure.net"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  name                 = "${var.name}-redis-dns"
  private_dns_zone_id  = azurerm_private_dns_zone.redis.id
  virtual_network_id   = var.vnet_id
  registration_enabled = false

  tags = var.tags
}

resource "azurerm_private_endpoint" "redis" {
  name                = "${var.name}-redis-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id

  private_service_connection {
    name                           = "${var.name}-redis"
    private_connection_resource_id = azurerm_managed_redis.main.id
    subresource_names              = ["redisEnterprise"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "redis"
    private_dns_zone_ids = [azurerm_private_dns_zone.redis.id]
  }

  tags = var.tags
}
