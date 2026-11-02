# Instance role: SSM (Session Manager, Run Command), its own secrets and certificates, the backups bucket.
# No EC2 or IAM permissions, no access keys. IMDSv2 with hop limit 1 keeps it away from the containers.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name}-plane-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "instance" {
  statement {
    sid     = "ReadPlaneSecrets"
    actions = ["secretsmanager:GetSecretValue"]
    resources = concat(
      [aws_secretsmanager_secret.app_keys.arn, aws_secretsmanager_secret.bundled.arn],
      local.certificate_arns,
    )
  }

  statement {
    sid       = "UseModuleKeyThroughServices"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.this.arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "secretsmanager.${local.region}.amazonaws.com",
        "s3.${local.region}.amazonaws.com",
      ]
    }
  }

  statement {
    sid       = "BackupsBucket"
    actions   = ["s3:ListBucket", "s3:GetEncryptionConfiguration"]
    resources = [aws_s3_bucket.backups.arn]
  }

  statement {
    sid     = "BackupsAndCommandOutput"
    actions = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:AbortMultipartUpload"]
    resources = [
      "${aws_s3_bucket.backups.arn}/backups/*",
      "${aws_s3_bucket.backups.arn}/ssm/*",
    ]
  }

  dynamic "statement" {
    for_each = local.assets_s3 == null ? [] : [local.assets_s3]

    content {
      sid       = "ReadComposeAssets"
      actions   = ["s3:GetObject"]
      resources = ["arn:${local.partition}:s3:::${statement.value[0]}/${statement.value[1] == "" ? "" : "${trimsuffix(statement.value[1], "/")}/"}*"]
    }
  }
}

resource "aws_iam_role_policy" "instance" {
  name   = "plane"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.instance.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-plane-instance"
  role = aws_iam_role.instance.name

  tags = var.tags
}

# Data Lifecycle Manager: daily snapshots of the data volume.

data "aws_iam_policy_document" "dlm_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dlm" {
  name               = "${var.name}-plane-dlm"
  assume_role_policy = data.aws_iam_policy_document.dlm_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

# Snapshots of a volume encrypted with the module key.
data "aws_iam_policy_document" "dlm_kms" {
  statement {
    actions   = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKeyWithoutPlaintext", "kms:ReEncrypt*"]
    resources = [aws_kms_key.this.arn]
  }

  statement {
    actions   = ["kms:CreateGrant"]
    resources = [aws_kms_key.this.arn]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role_policy" "dlm_kms" {
  name   = "module-key"
  role   = aws_iam_role.dlm.id
  policy = data.aws_iam_policy_document.dlm_kms.json
}
