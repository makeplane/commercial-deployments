resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "main" {
  bucket = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  tags = merge(var.tags, {
    Name = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"
  })
}

resource "aws_s3_bucket_versioning" "main" {
  count = var.enable_versioning ? 1 : 0

  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_vpc_endpoint ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = merge(var.tags, {
    Name = "${var.bucket_name_prefix}-s3-endpoint"
  })
}

data "aws_region" "current" {}
