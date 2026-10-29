# RDS for PostgreSQL Multi-AZ DB cluster (1 writer + 2 readable standbys), as today's module.
# The master password is managed by RDS in Secrets Manager (never in Terraform state); Plane
# connects as the master user and External Secrets + Reloader follow RDS's rotation.

locals {
  postgres_major = split(".", var.postgres.engine_version)[0]
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.name}-pg"
  subnet_ids = var.private_subnet_ids

  tags = var.tags
}

resource "aws_security_group" "postgres" {
  name        = "${var.name}-pg"
  description = "Plane PostgreSQL: reachable only from the EKS nodes"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-pg" })
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  security_group_id            = aws_security_group.postgres.id
  referenced_security_group_id = var.allowed_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from the EKS nodes"
}

resource "aws_rds_cluster_parameter_group" "postgres" {
  name        = "${var.name}-pg${local.postgres_major}"
  family      = "postgres${local.postgres_major}"
  description = "Plane PostgreSQL: TLS required"

  # Static on Multi-AZ DB clusters: AWS records it as pending-reboot, so say so, or every plan shows a
  # change. The cluster is created with this group, so it's in effect from the start.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = var.tags
}

resource "aws_rds_cluster" "postgres" {
  # checkov:skip=CKV2_AWS_27:Logging every statement risks capturing personal data and adds cost; enable through the parameter group if needed.
  # checkov:skip=CKV_AWS_162:Plane authenticates with the RDS-managed password, not IAM database auth.
  # checkov:skip=CKV_AWS_133:Defaults to 14 days (postgres.backup_retention_days); checkov can't read optional() defaults.
  # checkov:skip=CKV_AWS_139:Defaults to true (postgres.deletion_protection); checkov can't read optional() defaults.
  # checkov:skip=CKV2_AWS_8:An AWS Backup plan is planned (A25); RDS keeps automated backups (14 days) and a final snapshot meanwhile.
  cluster_identifier = "${var.name}-pg"

  engine                    = "postgres"
  engine_version            = var.postgres.engine_version
  db_cluster_instance_class = var.postgres.instance_class
  storage_type              = var.postgres.storage_type
  allocated_storage         = var.postgres.allocated_storage_gb
  iops                      = var.postgres.iops

  database_name                 = "plane"
  master_username               = "plane"
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.this.arn

  db_subnet_group_name            = aws_db_subnet_group.postgres.name
  vpc_security_group_ids          = [aws_security_group.postgres.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.postgres.name

  storage_encrypted = true
  kms_key_id        = aws_kms_key.this.arn

  backup_retention_period   = var.postgres.backup_retention_days
  copy_tags_to_snapshot     = true
  deletion_protection       = var.postgres.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-pg-final"

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.this.arn

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = var.tags
}
