# Backups bucket: nightly pg_dump files (backups/postgres/), the MinIO data mirror (backups/minio/) and the SSM
# command output (ssm/). Private, KMS, versioned (a MinIO object deleted in Plane stays recoverable for
# backup_retention_days).

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "backups" {
  # checkov:skip=CKV_AWS_18:Server access logging needs a separate log bucket; optional, customer choice.
  # checkov:skip=CKV_AWS_144:Cross-region replication is a disaster-recovery choice left to the customer.
  # checkov:skip=CKV2_AWS_62:Nothing consumes S3 event notifications.
  bucket        = "${var.name}-backups-${random_id.bucket_suffix.hex}"
  force_destroy = var.bucket_force_destroy

  tags = var.tags
}

resource "aws_s3_bucket_ownership_controls" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.this.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expire-database-dumps"
    status = "Enabled"
    filter {
      prefix = "backups/postgres/"
    }
    expiration {
      days = var.docker.backup_retention_days
    }
  }

  rule {
    id     = "expire-ssm-output"
    status = "Enabled"
    filter {
      prefix = "ssm/"
    }
    expiration {
      days = 30
    }
  }

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = var.docker.backup_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.backups]
}

data "aws_iam_policy_document" "backups" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.backups.arn,
      "${aws_s3_bucket.backups.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id
  policy = data.aws_iam_policy_document.backups.json

  depends_on = [aws_s3_bucket_public_access_block.backups]
}
