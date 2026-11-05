output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "Elastic IP (path A internet-facing), else null."
  value       = local.public ? aws_eip.this[0].public_ip : null
}

output "private_ip" {
  description = "Private IP of the instance."
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "Security group of the instance."
  value       = aws_security_group.instance.id
}

output "data_volume_id" {
  description = "EBS data volume (/opt/plane)."
  value       = aws_ebs_volume.data.id
}

output "backup_bucket_name" {
  description = "Backups bucket."
  value       = aws_s3_bucket.backups.id
}

output "kms_key_arn" {
  description = "KMS key encrypting the volumes, secrets and backups."
  value       = aws_kms_key.this.arn
}

output "secret_arns" {
  description = "Secrets Manager ARNs (never values)."
  value = {
    app_keys         = aws_secretsmanager_secret.app_keys.arn
    bundled_services = aws_secretsmanager_secret.bundled.arn
  }
}

output "converge_association_id" {
  description = "ID of the SSM association that converges the instance."
  value       = aws_ssm_association.converge.association_id
}

output "ssm_output_s3_uri" {
  description = "Where SSM writes the scripts' output."
  value       = "s3://${aws_s3_bucket.backups.id}/${local.ssm_output_prefix}/"
}

output "plane_env" {
  description = "The non-secret plane.env keys the module sets."
  value       = local.plane_env
}
