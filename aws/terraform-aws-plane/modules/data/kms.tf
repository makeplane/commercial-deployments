# One customer-managed key for RDS, ElastiCache, S3, Performance Insights, Secrets Manager and the database log group.
# The policy delegates to IAM (account root), so access is granted by IAM policies: the Pod
# Identity roles of External Secrets and Plane get kms:Decrypt on this key explicitly.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "kms" {
  # checkov:skip=CKV_AWS_109:Key policy (resource is the key itself); this is the AWS default statement that delegates to IAM.
  # checkov:skip=CKV_AWS_111:Key policy (resource is the key itself); this is the AWS default statement that delegates to IAM.
  # checkov:skip=CKV_AWS_356:In a key policy "*" means this key only.
  statement {
    sid       = "EnableIAMPolicies"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # CloudWatch Logs in this region may use the key only for the module's database log group.
  statement {
    sid       = "CloudWatchLogsPostgresLogGroup"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = [local.postgres_log_group_arn]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = "Plane (${var.name}) data encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json

  tags = var.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}-plane"
  target_key_id = aws_kms_key.this.key_id
}
