# One customer-managed key for RDS, ElastiCache, S3, Performance Insights and Secrets Manager.
# The default key policy (account root) applies: access is granted through IAM, e.g. the Pod
# Identity roles of External Secrets and Plane get kms:Decrypt on this key explicitly.
resource "aws_kms_key" "this" {
  description             = "Plane (${var.name}) data encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = var.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}-plane"
  target_key_id = aws_kms_key.this.key_id
}
