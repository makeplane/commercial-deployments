# JSON in the shape the chart reads through External Secrets. Replicated in-region only (data residency).

locals {
  secret_values = merge(
    {
      postgres = jsonencode({ username = google_sql_user.plane.name, password = random_password.postgres.result })
      redis    = jsonencode({ password = google_redis_instance.this.auth_string })
      rabbitmq = jsonencode({ username = "plane", password = random_password.rabbitmq.result })
      app_keys = jsonencode({ for k, v in random_password.app_keys : k => v.result })
    },
    var.opensearch.enabled ? {
      opensearch = jsonencode({ username = "plane", password = random_password.opensearch[0].result })
    } : {},
  )

  # Static keys, so for_each and IAM bindings are known at plan time.
  secret_names = merge(
    {
      postgres = "${var.name}-plane-db"
      redis    = "${var.name}-plane-redis"
      rabbitmq = "${var.name}-plane-rabbitmq"
      app_keys = "${var.name}-plane-app-keys"
    },
    var.opensearch.enabled ? { opensearch = "${var.name}-plane-opensearch" } : {},
  )
}

resource "google_secret_manager_secret" "this" {
  for_each = local.secret_names

  project   = var.project_id
  secret_id = each.value

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "this" {
  for_each = local.secret_names

  secret      = google_secret_manager_secret.this[each.key].id
  secret_data = local.secret_values[each.key]
}

# SECRET_KEY, AES_SECRET_KEY and AES_SALT encrypt stored data: if they change, it becomes unreadable silently.
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
    # Never regenerate, even if the lengths above change in a later module version.
    ignore_changes = all
  }
}
