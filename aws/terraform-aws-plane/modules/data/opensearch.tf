# Amazon OpenSearch Service for Plane's search (on by default; opensearch.enabled). Private: inside the
# VPC, reachable only from the EKS nodes over HTTPS. No users or passwords: Plane signs its
# requests with its Pod Identity role (SigV4). The domain policy that grants the role lives in the
# plane module, next to the role.

locals {
  opensearch_enabled = var.opensearch.enabled
  # Zone awareness needs the node count to be a multiple of the zone count.
  opensearch_zones = var.opensearch.instance_count % 3 == 0 ? 3 : (var.opensearch.instance_count % 2 == 0 ? 2 : 1)
}

resource "aws_security_group" "opensearch" {
  count = local.opensearch_enabled ? 1 : 0

  name        = "${var.name}-opensearch"
  description = "Plane OpenSearch: reachable only from the EKS nodes"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-opensearch" })
}

resource "aws_vpc_security_group_ingress_rule" "opensearch" {
  count = local.opensearch_enabled ? 1 : 0

  security_group_id            = aws_security_group.opensearch[0].id
  referenced_security_group_id = var.allowed_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "OpenSearch (HTTPS) from the EKS nodes"
}

resource "aws_opensearch_domain" "this" {
  # checkov:skip=CKV2_AWS_52:IAM-only access: Plane signs with SigV4 and the domain policy allows only its role. Fine-grained access control would add internal users.
  # checkov:skip=CKV_AWS_317:Audit logs need fine-grained access control (see CKV2_AWS_52).
  # checkov:skip=CKV_AWS_84:Log publishing needs an account-wide CloudWatch Logs resource policy; not in v0.1.
  # checkov:skip=CKV_AWS_318:Dedicated master nodes are for larger clusters; sized as today's customer default (2 data nodes).
  # checkov:skip=CKV2_AWS_59:Dedicated master nodes are for larger clusters; sized as today's customer default (2 data nodes).
  count = local.opensearch_enabled ? 1 : 0

  domain_name    = "${var.name}-search"
  engine_version = var.opensearch.engine_version

  cluster_config {
    instance_type          = var.opensearch.instance_type
    instance_count         = var.opensearch.instance_count
    zone_awareness_enabled = local.opensearch_zones > 1

    dynamic "zone_awareness_config" {
      for_each = local.opensearch_zones > 1 ? [1] : []
      content {
        availability_zone_count = local.opensearch_zones
      }
    }
  }

  vpc_options {
    subnet_ids         = slice(var.private_subnet_ids, 0, local.opensearch_zones)
    security_group_ids = [aws_security_group.opensearch[0].id]
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.opensearch.volume_size_gb
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = aws_kms_key.this.arn
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-PFS-2023-10"
  }

  tags = var.tags
}
