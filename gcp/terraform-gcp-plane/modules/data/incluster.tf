# The bundled servers and Plane's apps read these from the same Secret.

# The password goes into AMQP URLs: no special characters.
resource "random_password" "rabbitmq" {
  length  = 32
  special = false

  lifecycle {
    # The broker takes it only at first boot (users live on its disk): a new value would lock the apps out.
    ignore_changes = all
  }
}

# OpenSearch requires upper, lower, digit and special; specials limited to ones safe in shell and YAML.
resource "random_password" "opensearch" {
  count = var.opensearch.enabled ? 1 : 0

  length           = 32
  special          = true
  override_special = "-_=+.@%^"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2

  lifecycle {
    # Set only when the security index is first created (on its disk); see README to rotate it.
    ignore_changes = all
  }
}
