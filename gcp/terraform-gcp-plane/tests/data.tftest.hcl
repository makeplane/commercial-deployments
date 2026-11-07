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
    database_version            = "POSTGRES_15"
    tier                        = "db-custom-2-8192"
    edition                     = "ENTERPRISE"
    availability_type           = "REGIONAL"
    disk_size_gb                = 100
    disk_type                   = "PD_SSD"
    backup_retention_days       = 14
    point_in_time_recovery      = true
    deletion_protection         = true
    final_backup                = true
    final_backup_retention_days = 30
  }
  redis = {
    version             = "REDIS_7_2"
    tier                = "STANDARD_HA"
    memory_size_gb      = 4
    transit_encryption  = true
    persistence         = true
    rdb_snapshot_period = "TWENTY_FOUR_HOURS"
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

run "final_backup_on_delete" {
  module {
    source = "./modules/data"
  }

  assert {
    condition = (
      google_sql_database_instance.postgres.settings[0].final_backup_config[0].enabled &&
      google_sql_database_instance.postgres.settings[0].final_backup_config[0].retention_days == 30
    )
    error_message = "Cloud SQL must keep a final backup for 30 days by default."
  }
  assert {
    condition     = google_sql_database_instance.postgres.deletion_protection && google_sql_database_instance.postgres.settings[0].deletion_protection_enabled
    error_message = "Deletion protection stays on until the customer turns it off."
  }
}

run "final_backup_off" {
  module {
    source = "./modules/data"
  }
  variables {
    postgres = {
      database_version            = "POSTGRES_15"
      tier                        = "db-custom-2-8192"
      edition                     = "ENTERPRISE"
      availability_type           = "REGIONAL"
      disk_size_gb                = 100
      disk_type                   = "PD_SSD"
      backup_retention_days       = 14
      point_in_time_recovery      = true
      deletion_protection         = false
      final_backup                = false
      final_backup_retention_days = 30
    }
  }

  assert {
    condition = (
      !google_sql_database_instance.postgres.settings[0].final_backup_config[0].enabled &&
      google_sql_database_instance.postgres.settings[0].final_backup_config[0].retention_days == null
    )
    error_message = "With the final backup off, the module must turn it off explicitly and send no retention."
  }
}

run "redis_rdb_persistence" {
  module {
    source = "./modules/data"
  }

  assert {
    condition = (
      google_redis_instance.this.persistence_config[0].persistence_mode == "RDB" &&
      google_redis_instance.this.persistence_config[0].rdb_snapshot_period == "TWENTY_FOUR_HOURS"
    )
    error_message = "Memorystore must take a daily RDB snapshot by default."
  }
}

run "redis_rdb_persistence_on_basic_tier" {
  module {
    source = "./modules/data"
  }
  variables {
    redis = {
      version             = "REDIS_7_2"
      tier                = "BASIC"
      memory_size_gb      = 4
      transit_encryption  = true
      persistence         = true
      rdb_snapshot_period = "SIX_HOURS"
    }
  }

  assert {
    condition = (
      google_redis_instance.this.tier == "BASIC" &&
      google_redis_instance.this.persistence_config[0].persistence_mode == "RDB" &&
      google_redis_instance.this.persistence_config[0].rdb_snapshot_period == "SIX_HOURS"
    )
    error_message = "BASIC takes RDB snapshots too, at the chosen period."
  }
}

run "redis_persistence_off" {
  module {
    source = "./modules/data"
  }
  variables {
    redis = {
      version             = "REDIS_7_2"
      tier                = "STANDARD_HA"
      memory_size_gb      = 4
      transit_encryption  = true
      persistence         = false
      rdb_snapshot_period = "TWENTY_FOUR_HOURS"
    }
  }

  assert {
    condition = (
      google_redis_instance.this.persistence_config[0].persistence_mode == "DISABLED" &&
      google_redis_instance.this.persistence_config[0].rdb_snapshot_period == null
    )
    error_message = "With persistence off, the mode is DISABLED and no period is sent."
  }
}
