# Credentials for the RabbitMQ and OpenSearch the chart runs in the cluster (GCP has neither as a managed service).
# Both sides (the bundled server and Plane's apps) read them from one Secret synced by External Secrets.

# The password goes into AMQP URLs: no special characters.
resource "random_password" "rabbitmq" {
  length  = 32
  special = false
}

# The bundled OpenSearch's security plugin requires a strong admin password (upper, lower, digit, special). Special
# characters limited to ones that are safe in the chart's shell init script and in YAML.
resource "random_password" "opensearch" {
  count = var.opensearch.enabled ? 1 : 0

  length           = 32
  special          = true
  override_special = "-_=+.@%^"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}
