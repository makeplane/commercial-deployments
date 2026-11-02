# Cloud SQL instance names can't be reused for about a week after deletion.
resource "random_id" "postgres_suffix" {
  byte_length = 2
}

resource "google_sql_database_instance" "postgres" {
  # checkov:skip=CKV_GCP_6:TLS is enforced by ssl_mode; checkov only reads the deprecated require_ssl.
  # checkov:skip=CKV_GCP_79:The version is an input (postgres.database_version).
  project          = var.project_id
  name             = "${var.name}-pg-${random_id.postgres_suffix.hex}"
  region           = var.region
  database_version = var.postgres.database_version

  deletion_protection = var.postgres.deletion_protection

  settings {
    tier                        = var.postgres.tier
    edition                     = var.postgres.edition
    availability_type           = var.postgres.availability_type
    disk_size                   = var.postgres.disk_size_gb
    disk_type                   = var.postgres.disk_type
    disk_autoresize             = true
    deletion_protection_enabled = var.postgres.deletion_protection

    ip_configuration {
      ipv4_enabled       = false
      private_network    = var.network_id
      allocated_ip_range = var.private_service_range
      # Clients needn't present a certificate.
      ssl_mode = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = var.postgres.point_in_time_recovery
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = var.postgres.backup_retention_days
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = 7
      hour         = 4
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      record_client_address   = false
      record_application_tags = false
    }

    # Statement logging stays off: it can capture personal data.
    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }
    database_flags {
      name  = "log_connections"
      value = "on"
    }
    database_flags {
      name  = "log_disconnections"
      value = "on"
    }
    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }
    database_flags {
      name  = "log_temp_files"
      value = "0"
    }
    database_flags {
      name  = "log_min_duration_statement"
      value = "-1"
    }

    user_labels = var.labels
  }
}

resource "google_sql_database" "this" {
  for_each = toset(["plane", "plane_pi"])

  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  name     = each.value

  # Deleting a database fails while connections remain; the instance takes them with it.
  deletion_policy = "ABANDON"
}

resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "google_sql_user" "plane" {
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  name     = "plane"
  password = random_password.postgres.result

  # Postgres refuses to drop a user that owns objects; the instance takes it with it.
  deletion_policy = "ABANDON"
}
