resource "google_redis_instance" "this" {
  project        = var.project_id
  name           = "${var.name}-redis"
  display_name   = "Plane ${var.name}"
  region         = var.region
  tier           = var.redis.tier
  memory_size_gb = var.redis.memory_size_gb
  redis_version  = var.redis.version

  authorized_network = var.network_id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"
  reserved_ip_range  = var.private_service_range

  auth_enabled            = true
  transit_encryption_mode = var.redis.transit_encryption ? "SERVER_AUTHENTICATION" : "DISABLED"

  persistence_config {
    persistence_mode    = var.redis.persistence ? "RDB" : "DISABLED"
    rdb_snapshot_period = var.redis.persistence ? var.redis.rdb_snapshot_period : null
  }

  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 4
        minutes = 0
      }
    }
  }

  labels = var.labels
}
