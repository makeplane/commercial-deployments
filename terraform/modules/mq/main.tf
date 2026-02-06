resource "aws_security_group" "mq_sg" {
  name        = "${var.cluster_name}-amazon-mq-sg"
  description = "Security group for Amazon MQ"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "AMQP from VPC CIDR"
  }

  ingress {
    from_port   = 15672
    to_port     = 15672
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "RabbitMQ management UI from VPC CIDR"
  }

  ingress {
    from_port   = 15671
    to_port     = 15671
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "RabbitMQ Prometheus metrics from VPC CIDR"
  }

  dynamic "ingress" {
    for_each = length(var.allowed_security_group_ids) > 0 ? [1] : []
    content {
      from_port       = 5672
      to_port         = 5672
      protocol        = "tcp"
      security_groups = var.allowed_security_group_ids
      description     = "AMQP from EKS nodes"
    }
  }

  dynamic "ingress" {
    for_each = length(var.allowed_security_group_ids) > 0 ? [1] : []
    content {
      from_port       = 15672
      to_port         = 15672
      protocol        = "tcp"
      security_groups = var.allowed_security_group_ids
      description     = "RabbitMQ management UI from EKS nodes"
    }
  }

  dynamic "ingress" {
    for_each = length(var.allowed_security_group_ids) > 0 ? [1] : []
    content {
      from_port       = 15671
      to_port         = 15671
      protocol        = "tcp"
      security_groups = var.allowed_security_group_ids
      description     = "RabbitMQ Prometheus metrics from EKS nodes"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-amazon-mq-sg"
  })
}

resource "aws_mq_broker" "rabbitmq" {
  apply_immediately          = true
  auto_minor_version_upgrade = true
  broker_name                = "${var.cluster_name}-rabbitmq"
  engine_type                = "RabbitMQ"
  engine_version             = var.engine_version
  host_instance_type         = var.instance_type
  deployment_mode            = var.deployment_mode
  subnet_ids                 = var.subnet_ids
  publicly_accessible        = false

  security_groups = [aws_security_group.mq_sg.id]

  user {
    username = var.mq_username
    password = var.mq_password
  }

  logs {
    general = true
  }

  tags = merge(var.tags, {
    Name      = "${var.cluster_name}-rabbitmq"
    Component = "messaging"
    ManagedBy = "Terraform"
  })
}
