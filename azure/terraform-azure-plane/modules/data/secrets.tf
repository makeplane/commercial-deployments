# Alphanumeric: the value ends up inside a connection URL.
resource "random_password" "rabbitmq" {
  length  = 32
  special = false

  lifecycle {
    # The broker takes it only at first boot (users live on its disk): a new value would lock the apps out.
    ignore_changes = all
  }
}

# The OpenSearch security plugin rejects passwords without a special character.
resource "random_password" "opensearch" {
  length           = 32
  special          = true
  override_special = "-_"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1

  lifecycle {
    # Set only when the security index is first created (on its disk); see README to rotate it.
    ignore_changes = all
  }
}

# SECRET_KEY, AES_SECRET_KEY and AES_SALT encrypt stored data and must never change, so
# ignore_changes = all keeps any later edit to these arguments from regenerating them.
resource "random_password" "app_keys" {
  for_each = {
    SECRET_KEY             = 50
    AES_SECRET_KEY         = 32
    AES_SALT               = 32
    LIVE_SERVER_SECRET_KEY = 48
    PI_INTERNAL_SECRET     = 48
    SILO_HMAC_SECRET_KEY   = 48
    CURSOR_WEBHOOK_SECRET  = 48
    RUNNER_HMAC_SECRET_KEY = 48
  }

  length  = each.value
  special = false

  lifecycle {
    ignore_changes = all
  }
}

locals {
  secret_names = concat(
    ["plane-db", "plane-redis", "plane-rabbitmq", "plane-app-keys"],
    var.opensearch_enabled ? ["plane-opensearch"] : [],
  )

  secret_values = {
    "plane-db"       = jsonencode({ username = azurerm_postgresql_flexible_server.this.administrator_login, password = random_password.postgres.result })
    "plane-redis"    = jsonencode({ password = azurerm_managed_redis.this.default_database[0].primary_access_key })
    "plane-rabbitmq" = jsonencode({ username = "plane", password = random_password.rabbitmq.result })
    "plane-app-keys" = jsonencode({ for k, v in random_password.app_keys : k => v.result })
    # Admin and Plane user share this password, as in the chart.
    "plane-opensearch" = jsonencode({ username = "plane", password = random_password.opensearch.result })
  }
}

resource "azurerm_key_vault_secret" "this" {
  # checkov:skip=CKV_AZURE_41:Generated credentials don't expire; app keys must never rotate.
  for_each = toset(local.secret_names)

  name         = each.value
  value        = local.secret_values[each.value]
  key_vault_id = azurerm_key_vault.this.id
  content_type = "application/json"

  depends_on = [time_sleep.key_vault_rbac]
}
