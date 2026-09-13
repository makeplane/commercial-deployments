data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  opensearch_sg_id = var.enable_vpc ? aws_security_group.opensearch[0].id : null

  effective_connector_subnet_ids = coalesce(var.connector_subnet_ids, var.subnet_ids)
  effective_connector_sg_ids     = coalesce(var.connector_security_group_ids, var.enable_vpc ? [aws_security_group.opensearch[0].id] : null)
}

resource "aws_security_group" "opensearch" {
  count = var.enable_vpc ? 1 : 0

  name_prefix = "${var.domain_name}-opensearch-"
  description = "OpenSearch domain security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.domain_name}-opensearch-sg"
  })
}

resource "aws_security_group_rule" "opensearch_https_self" {
  count = var.enable_vpc ? 1 : 0

  type              = "ingress"
  security_group_id = aws_security_group.opensearch[0].id
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  self              = true
  description       = "Allow HTTPS within the OpenSearch/connector security group"
}

resource "aws_security_group_rule" "opensearch_https_egress" {
  count = var.enable_vpc ? 1 : 0

  type              = "egress"
  security_group_id = aws_security_group.opensearch[0].id
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTPS egress for Lambda to reach OpenSearch and Bedrock endpoints"
}

resource "aws_security_group_rule" "opensearch_https_from_allowed_sgs" {
  # Use stable keys (list indices) so values may be unknown at plan time (e.g., with -target).
  for_each = var.enable_vpc ? { for idx, sg_id in var.allowed_ingress_security_group_ids : tostring(idx) => sg_id } : {}

  type                     = "ingress"
  security_group_id        = aws_security_group.opensearch[0].id
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
  source_security_group_id = each.value
  description              = "Allow HTTPS to OpenSearch from approved security group"
}

resource "aws_security_group_rule" "opensearch_https_from_vpc" {
  type                     = "ingress"
  security_group_id        = aws_security_group.opensearch[0].id
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
  source_security_group_id = var.vpc_id
  description              = "Allow HTTPS to OpenSearch from VPC"
}

resource "aws_opensearch_domain" "main" {
  domain_name    = var.domain_name
  engine_version = var.engine_version

  cluster_config {
    instance_type  = var.instance_type
    instance_count = var.instance_count
  }

  ebs_options {
    ebs_enabled = true
    volume_type = var.ebs_volume_type
    volume_size = var.ebs_volume_size
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = var.master_username
      master_user_password = var.master_password
    }
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "es:*"
        Resource = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.domain_name}/*"
      }
    ]
  })

  node_to_node_encryption {
    enabled = true
  }

  encrypt_at_rest {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  dynamic "vpc_options" {
    for_each = var.enable_vpc ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = [aws_security_group.opensearch[0].id]
    }
  }

  tags = var.tags
}

resource "aws_cloudformation_stack" "bedrock_connector" {
  count = var.create_connector ? 1 : 0

  name          = "${var.domain_name}-bedrock-connector"
  template_body = file("${path.module}/bedrock-connector.cloudformation.yml")
  capabilities  = ["CAPABILITY_NAMED_IAM"]

  parameters = {
    AddOfflineBatchInference                = var.add_offline_batch_inference ? "true" : "false"
    AddProcessFunction                      = var.add_process_function ? "true" : "false"
    AmazonOpenSearchEndpoint                = "https://${aws_opensearch_domain.main.endpoint}"
    BedrockModelRegion                      = var.bedrock_model_region
    LambdaInvokeOpenSearchMLCommonsRoleName = var.lambda_invoke_opensearch_mlcommons_role_name
    Model                                   = var.bedrock_model
    ModelName                               = var.bedrock_model_name
    SecurityGroupIds                        = join(",", local.effective_connector_sg_ids)
    SubnetIds                               = join(",", local.effective_connector_subnet_ids)
  }

  depends_on = [aws_opensearch_domain.main]
}
