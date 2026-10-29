# Amazon MQ for RabbitMQ, private, over AMQPS (5671).

resource "aws_security_group" "rabbitmq" {
  name        = "${var.name}-mq"
  description = "Plane RabbitMQ: reachable only from the EKS nodes"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-mq" })
}

resource "aws_vpc_security_group_ingress_rule" "rabbitmq" {
  security_group_id            = aws_security_group.rabbitmq.id
  referenced_security_group_id = var.allowed_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5671
  to_port                      = 5671
  description                  = "AMQPS from the EKS nodes"
}

# Amazon MQ rejects commas, colons and equals signs in RabbitMQ passwords.
resource "random_password" "rabbitmq" {
  length  = 32
  special = false
}

resource "aws_mq_broker" "rabbitmq" {
  broker_name = "${var.name}-mq"

  engine_type        = "RabbitMQ"
  engine_version     = var.rabbitmq.engine_version
  host_instance_type = var.rabbitmq.instance_type
  deployment_mode    = var.rabbitmq.deployment_mode

  # A cluster spreads its three nodes over the private subnets; a single instance takes one.
  subnet_ids          = var.rabbitmq.deployment_mode == "SINGLE_INSTANCE" ? [var.private_subnet_ids[0]] : var.private_subnet_ids
  security_groups     = [aws_security_group.rabbitmq.id]
  publicly_accessible = false

  auto_minor_version_upgrade = true

  # Amazon MQ for RabbitMQ only supports an AWS owned key for encryption at rest.
  encryption_options {
    use_aws_owned_key = true
  }

  logs {
    general = true
  }

  user {
    username = "plane"
    password = random_password.rabbitmq.result
  }

  tags = var.tags
}

locals {
  # endpoints[0] looks like "amqps://b-xxxx.mq.us-east-1.on.aws:5671".
  rabbitmq_host = split(":", trimprefix(aws_mq_broker.rabbitmq.instances[0].endpoints[0], "amqps://"))[0]
}
