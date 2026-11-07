# The data layer on its own: Cloud SQL, Memorystore, the bucket and the generated secrets. Mock providers: no GCP
# credentials needed.

mock_provider "google" {}
mock_provider "random" {}

variables {
  name                  = "plane-test"
  project_id            = "plane-test-project"
  region                = "us-central1"
  domain                = "plane.example.com"
  network_id            = "projects/plane-test-project/global/networks/plane-test"
  private_service_range = "plane-test-psa"
  bucket_force_destroy  = false
  labels                = {}

  postgres = {
    database_version       = "POSTGRES_15"
    tier                   = "db-custom-2-8192"
    edition                = "ENTERPRISE"
    availability_type      = "REGIONAL"
    disk_size_gb           = 100
    disk_type              = "PD_SSD"
    backup_retention_days  = 14
    point_in_time_recovery = true
    deletion_protection    = true
  }
  redis = {
    version            = "REDIS_7_2"
    tier               = "STANDARD_HA"
    memory_size_gb     = 4
    transit_encryption = true
  }
  opensearch = {
    enabled        = true
    volume_size_gb = 20
    index_prefix   = "plane"
  }
}

run "app_key_names" {
  module {
    source = "./modules/data"
  }

  assert {
    condition = toset(output.plane_inputs.app_key_names) == toset([
      "SECRET_KEY", "AES_SECRET_KEY", "AES_SALT", "LIVE_SERVER_SECRET_KEY", "PI_INTERNAL_SECRET",
      "SILO_HMAC_SECRET_KEY", "CURSOR_WEBHOOK_SECRET", "RUNNER_HMAC_SECRET_KEY",
    ])
    error_message = "Plane must sync every generated app key by name."
  }
}
