output "postgres_instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.postgres.name
}

output "postgres_host" {
  description = "Cloud SQL private IP."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "redis_host" {
  description = "Memorystore host (private IP)."
  value       = google_redis_instance.this.host
}

output "redis_port" {
  description = "Memorystore port (6378 with TLS, 6379 without)."
  value       = google_redis_instance.this.port
}

output "bucket_name" {
  description = "Uploads bucket name."
  value       = google_storage_bucket.uploads.name
}

output "secret_ids" {
  description = "Every Secret Manager secret Plane reads (projects/<project>/secrets/<name>)."
  value       = { for k, s in google_secret_manager_secret.this : k => s.id }
}

output "plane_inputs" {
  description = "Everything the Plane Helm release needs from the data layer."
  value = {
    bucket_name = google_storage_bucket.uploads.name

    postgres_host = google_sql_database_instance.postgres.private_ip_address
    postgres_port = 5432
    postgres_db   = google_sql_database.this["plane"].name

    redis_host = google_redis_instance.this.host
    redis_port = google_redis_instance.this.port
    redis_tls  = var.redis.transit_encryption
    # A public certificate, not a secret.
    redis_ca = var.redis.transit_encryption ? join("\n", [for c in google_redis_instance.this.server_ca_certs : c.cert]) : null

    opensearch_enabled = var.opensearch.enabled

    # Short IDs: the SecretStore is scoped to project_id.
    secret_names  = { for k, s in google_secret_manager_secret.this : k => s.secret_id }
    app_key_names = keys(random_password.app_keys)
  }

  # Every secret has a value before the ExternalSecrets that read it are created.
  depends_on = [google_secret_manager_secret_version.this, google_sql_user.plane, google_sql_database.this]
}
