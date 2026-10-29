output "kms_key_arn" {
  description = "KMS key ARN."
  value       = aws_kms_key.this.arn
}

output "postgres_host" {
  description = "RDS cluster writer endpoint."
  value       = aws_rds_cluster.postgres.endpoint
}

output "redis_host" {
  description = "ElastiCache primary endpoint."
  value       = aws_elasticache_replication_group.valkey.primary_endpoint_address
}

output "rabbitmq_host" {
  description = "Amazon MQ AMQPS host."
  value       = local.rabbitmq_host
}

output "bucket_name" {
  description = "Uploads bucket name."
  value       = aws_s3_bucket.uploads.id
}

output "secret_arns" {
  description = "Every Secrets Manager secret Plane reads."
  value = {
    postgres = aws_rds_cluster.postgres.master_user_secret[0].secret_arn
    redis    = aws_secretsmanager_secret.valkey.arn
    rabbitmq = aws_secretsmanager_secret.rabbitmq.arn
    app_keys = aws_secretsmanager_secret.app_keys.arn
  }
}

output "plane_inputs" {
  description = "Everything the Plane Helm release needs from the data layer."
  value = {
    kms_key_arn = aws_kms_key.this.arn

    bucket_name = aws_s3_bucket.uploads.id
    bucket_arn  = aws_s3_bucket.uploads.arn

    postgres_host       = aws_rds_cluster.postgres.endpoint
    postgres_port       = aws_rds_cluster.postgres.port
    postgres_db         = aws_rds_cluster.postgres.database_name
    postgres_secret_arn = aws_rds_cluster.postgres.master_user_secret[0].secret_arn

    redis_host       = aws_elasticache_replication_group.valkey.primary_endpoint_address
    redis_port       = aws_elasticache_replication_group.valkey.port
    redis_secret_arn = aws_secretsmanager_secret.valkey.arn

    rabbitmq_host       = local.rabbitmq_host
    rabbitmq_port       = 5671
    rabbitmq_secret_arn = aws_secretsmanager_secret.rabbitmq.arn

    app_keys_secret_arn = aws_secretsmanager_secret.app_keys.arn
  }

  # The nodes must be able to reach the services before Plane's DB-init Job and workloads start.
  depends_on = [
    aws_vpc_security_group_ingress_rule.postgres,
    aws_vpc_security_group_ingress_rule.valkey,
    aws_vpc_security_group_ingress_rule.rabbitmq,
  ]
}
