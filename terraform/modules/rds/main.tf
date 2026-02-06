resource "aws_db_subnet_group" "rds" {
  name       = "${var.cluster_name}-rds-subnet"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-rds-subnet"
  })
}

resource "aws_security_group" "rds" {
  name        = "${var.cluster_name}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "PostgreSQL from VPC CIDR"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-rds-sg"
  })
}

resource "aws_rds_cluster" "main" {
  cluster_identifier          = "${var.cluster_name}-postgres"
  engine                      = "postgres"
  engine_version              = var.engine_version
  database_name               = var.db_name
  master_username             = var.db_username
  manage_master_user_password = true
  port                        = 5432

  db_cluster_instance_class = var.instance_class
  allocated_storage         = var.allocated_storage
  storage_type              = var.storage_type
  iops                      = var.iops
  storage_encrypted         = true

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  availability_zones     = var.availability_zones

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "Mon:04:00-Mon:05:00"
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${var.cluster_name}-postgres-final-snapshot"

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-postgres"
  })
}
