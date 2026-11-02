# Password auth: Plane has no Entra token support. Both databases are created here (no DB-init Job).

resource "random_password" "postgres" {
  length  = 40
  special = false
}

# Must end in .postgres.database.azure.com; the server-name prefix keeps it unique.
resource "azurerm_private_dns_zone" "postgres" {
  name                = "${local.postgres_name}.private.postgres.database.azure.com"
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

resource "azurerm_postgresql_flexible_server" "this" {
  # checkov:skip=CKV_AZURE_136:Geo-redundant backups are an input; off by default, as on AWS.
  # checkov:skip=CKV2_AZURE_57:VNet-integrated (delegated subnet) instead of a private endpoint.
  name                = local.postgres_name
  location            = var.location
  resource_group_name = var.resource_group_name
  version             = var.postgres.engine_version
  sku_name            = var.postgres.sku_name
  zone                = var.zones[0]

  storage_mb        = var.postgres.storage_mb
  auto_grow_enabled = true

  delegated_subnet_id           = var.postgres_subnet_id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false

  administrator_login    = "plane"
  administrator_password = random_password.postgres.result

  authentication {
    password_auth_enabled         = true
    active_directory_auth_enabled = false
  }

  backup_retention_days        = var.postgres.backup_retention_days
  geo_redundant_backup_enabled = var.postgres.geo_redundant_backup_enabled

  dynamic "high_availability" {
    for_each = var.postgres.high_availability_mode != "Disabled" ? [1] : []
    content {
      mode                      = var.postgres.high_availability_mode
      standby_availability_zone = var.postgres.high_availability_mode == "ZoneRedundant" ? var.zones[1] : null
    }
  }

  # Mon 04:00 UTC, as on AWS.
  maintenance_window {
    day_of_week  = 1
    start_hour   = 4
    start_minute = 0
  }

  tags = var.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]

  lifecycle {
    ignore_changes = [
      # Azure swaps the primary and standby zones on failover.
      zone,
      high_availability[0].standby_availability_zone,
    ]
  }
}

# Already the default; set so drift shows in the plan.
resource "azurerm_postgresql_flexible_server_configuration" "require_secure_transport" {
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = "on"
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  for_each = toset(["plane", "plane_pi"])

  name      = each.value
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Set postgres.deletion_protection = false and apply before a destroy.
resource "azurerm_management_lock" "postgres" {
  count = var.postgres.deletion_protection ? 1 : 0

  name       = "${var.name}-postgres-protect"
  scope      = azurerm_postgresql_flexible_server.this.id
  lock_level = "CanNotDelete"
  notes      = "Plane database. Set postgres.deletion_protection = false and apply before destroying."
}
