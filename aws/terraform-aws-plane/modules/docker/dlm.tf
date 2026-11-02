# Crash-consistent snapshots; the nightly pg_dump is the consistent copy.
resource "aws_dlm_lifecycle_policy" "data" {
  description        = "Plane ${var.name} data volume"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags = {
      "plane.so/deployment" = var.name
      "plane.so/volume"     = "data"
    }

    schedule {
      name      = "daily"
      copy_tags = true

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = [var.docker.backup_time]
      }

      retain_rule {
        count = var.docker.backup_retention_days
      }

      tags_to_add = {
        "plane.so/snapshot" = "daily"
      }
    }
  }

  tags = var.tags
}
