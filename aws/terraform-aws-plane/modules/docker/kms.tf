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
      identifiers = ["arn:${local.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
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
