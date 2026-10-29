# ElastiCache Valkey with TLS, an AUTH token and at-rest encryption: the same setup as Plane's
# own production cache (terraform-scripts/cache), sized as today's customer default.

resource "aws_elasticache_subnet_group" "valkey" {
  name       = "${var.name}-valkey"
  subnet_ids = var.private_subnet_ids

  tags = var.tags
}

resource "aws_security_group" "valkey" {
  name        = "${var.name}-valkey"
  description = "Plane Valkey: reachable only from the EKS nodes"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-valkey" })
}

resource "aws_vpc_security_group_ingress_rule" "valkey" {
  security_group_id            = aws_security_group.valkey.id
  referenced_security_group_id = var.allowed_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  description                  = "Valkey (TLS) from the EKS nodes"
}

# ElastiCache AUTH tokens allow printable characters except @, " and /. Alphanumeric keeps it
# safe inside the rediss:// URLs the apps build.
resource "random_password" "valkey_auth" {
  length  = 64
  special = false
}

# Own parameter group (a copy of the defaults) so settings can be tuned later without
# replacing the cache.
resource "aws_elasticache_parameter_group" "valkey" {
  name        = "${var.name}-valkey${split(".", var.redis.engine_version)[0]}"
  family      = "valkey${split(".", var.redis.engine_version)[0]}"
  description = "Plane (${var.name}) Valkey"

  tags = var.tags
}

resource "aws_elasticache_replication_group" "valkey" {
  # checkov:skip=CKV2_AWS_50:Single node is the default size; set redis.replicas >= 1 for Multi-AZ automatic failover.
  replication_group_id = "${var.name}-valkey"
  description          = "Plane (${var.name}) cache"

  engine               = "valkey"
  engine_version       = var.redis.engine_version
  parameter_group_name = aws_elasticache_parameter_group.valkey.name
  node_type            = var.redis.node_type
  port                 = 6379

  num_cache_clusters         = 1 + var.redis.replicas
  automatic_failover_enabled = var.redis.replicas > 0
  multi_az_enabled           = var.redis.replicas > 0

  subnet_group_name  = aws_elasticache_subnet_group.valkey.name
  security_group_ids = [aws_security_group.valkey.id]

  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  kms_key_id                 = aws_kms_key.this.arn
  auth_token                 = random_password.valkey_auth.result
  auth_token_update_strategy = "ROTATE"

  snapshot_retention_limit   = 7
  auto_minor_version_upgrade = true

  tags = var.tags
}
