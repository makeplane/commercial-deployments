# Private DNS zone for the VNet-integrated server. The zone name must end in
# .postgres.database.azure.com; prefixing it with the server name keeps it unique.
resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.name}.private.postgres.database.azure.com"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                 = "${var.name}-postgres-dns"
  private_dns_zone_id  = azurerm_private_dns_zone.postgres.id
  virtual_network_id   = var.vnet_id
  registration_enabled = false

  tags = var.tags
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                = "${var.name}-postgres"
  location            = var.location
  resource_group_name = var.resource_group_name
  version             = var.engine_version
  sku_name            = var.sku_name
  zone                = var.zone

  storage_mb        = var.storage_mb
  auto_grow_enabled = true

  # Private access only: the server gets an IP in the delegated subnet and is
  # reachable from the VNet (AKS pods), never from the internet.
  delegated_subnet_id           = var.subnet_id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false

  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password

  authentication {
    password_auth_enabled         = true
    active_directory_auth_enabled = false
  }

  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled

  dynamic "high_availability" {
    for_each = var.high_availability_mode != "Disabled" ? [1] : []
    content {
      mode                      = var.high_availability_mode
      standby_availability_zone = var.high_availability_mode == "ZoneRedundant" ? var.standby_zone : null
    }
  }

  # Mon 04:00 UTC, matching the RDS maintenance window.
  maintenance_window {
    day_of_week  = 1
    start_hour   = 4
    start_minute = 0
  }

  tags = var.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]

  lifecycle {
    ignore_changes = [
      # Azure swaps primary and standby zones on failover.
      zone,
      high_availability[0].standby_availability_zone,
    ]
  }
}

resource "azurerm_postgresql_flexible_server_database" "main" {
  for_each = toset(var.database_names)

  name      = each.value
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
