output "domain_endpoint" {
  description = "OpenSearch domain endpoint"
  value       = aws_opensearch_domain.main.endpoint
}

output "domain_arn" {
  description = "OpenSearch domain ARN"
  value       = aws_opensearch_domain.main.arn
}

output "kibana_endpoint" {
  description = "OpenSearch Dashboards endpoint"
  value       = aws_opensearch_domain.main.dashboard_endpoint
}

output "bedrock_connector_id" {
  description = "Connector ID created in OpenSearch ML Commons (null when create_connector = false)."
  value       = try(aws_cloudformation_stack.bedrock_connector[0].outputs["ConnectorId"], null)
}

output "bedrock_model_id" {
  description = "Model ID created in OpenSearch ML Commons (null when create_connector = false)."
  value       = try(aws_cloudformation_stack.bedrock_connector[0].outputs["ModelId"], null)
}

output "bedrock_endpoint" {
  description = "Bedrock model endpoint connected to OpenSearch (null when create_connector = false)."
  value       = try(aws_cloudformation_stack.bedrock_connector[0].outputs["BedrockEndpoint"], null)
}
