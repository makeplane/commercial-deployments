output "broker_id" {
  description = "Broker ID"
  value       = aws_mq_broker.rabbitmq.id
}

output "broker_arn" {
  description = "Broker ARN"
  value       = aws_mq_broker.rabbitmq.arn
}

output "broker_endpoints" {
  description = "Broker endpoints (AMQP)"
  value       = aws_mq_broker.rabbitmq.instances
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.mq_sg.id
}
