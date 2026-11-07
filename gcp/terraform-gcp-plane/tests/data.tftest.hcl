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

# ignore_changes can't be seen in a plan with mocks, so the source is read directly.
run "in_cluster_passwords_never_regenerate" {
  module {
    source = "./modules/data"
  }

  assert {
    condition     = length(regexall("ignore_changes\\s*=\\s*all", file("${path.module}/incluster.tf"))) == 2
    error_message = "random_password.rabbitmq and .opensearch must ignore all changes: the servers take them only at first boot."
  }
  assert {
    condition     = random_password.rabbitmq.length == 32 && !random_password.rabbitmq.special
    error_message = "The RabbitMQ password goes into AMQP URLs: no special characters."
  }
  assert {
    condition     = length(random_password.opensearch) == 1 && random_password.opensearch[0].min_special == 2
    error_message = "OpenSearch rejects passwords without a special character."
  }
}
