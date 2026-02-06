output "cluster_endpoint" {
  description = "Writer endpoint for the RDS cluster"
  value       = aws_rds_cluster.main.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint (load-balanced across readers)"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "db_name" {
  description = "Database name"
  value       = aws_rds_cluster.main.database_name
}

output "port" {
  description = "Database port"
  value       = aws_rds_cluster.main.port
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.rds.id
}

output "master_user_secret" {
  description = "Master user secret in Secrets Manager"
  value       = aws_rds_cluster.main.master_user_secret
  sensitive   = true
}
