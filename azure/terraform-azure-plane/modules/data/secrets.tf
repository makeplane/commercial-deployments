# Key Vault secrets, in the JSON shape the plane-enterprise chart reads through External Secrets
# (dataFrom.extract mirrors the keys with no templating).

# Generated credentials. Alphanumeric where the value ends up inside a connection URL.
resource "random_password" "rabbitmq" {
  length  = 32
  special = false
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
}

# Signing and encryption keys shared by api, live, silo and pi (chart external_secrets.app_keys_existingSecret),
# the same list as on AWS. SECRET_KEY, AES_SECRET_KEY and AES_SALT encrypt stored data: they are generated
# once and must never change, or existing ciphertext becomes unreadable without any error. ignore_changes
# keeps an edited length or character set from regenerating a key.
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
    ignore_changes = [length, special]
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
    # The in-cluster OpenSearch's admin and Plane user share this password, as the chart does.
    "plane-opensearch" = jsonencode({ username = "plane", password = random_password.opensearch.result })
  }
}

resource "azurerm_key_vault_secret" "this" {
  # checkov:skip=CKV_AZURE_41:Generated credentials and app keys don't expire; the app keys must never rotate.
  for_each = toset(local.secret_names)

  name         = each.value
  value        = local.secret_values[each.value]
  key_vault_id = azurerm_key_vault.this.id
  content_type = "application/json"

  depends_on = [time_sleep.key_vault_rbac]
}
