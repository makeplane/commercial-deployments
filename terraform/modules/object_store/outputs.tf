output "bucket_id" {
  description = "S3 bucket ID"
  value       = aws_s3_bucket.main.id
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.main.arn
}

output "bucket_domain_name" {
  description = "S3 bucket domain name"
  value       = aws_s3_bucket.main.bucket_domain_name
}

output "vpc_endpoint_id" {
  description = "S3 VPC endpoint ID (if enabled)"
  value       = var.enable_vpc_endpoint ? aws_vpc_endpoint.s3[0].id : null
}
