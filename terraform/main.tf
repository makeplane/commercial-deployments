locals {
  # Use provided AZs or default to first 3 in the region
  availability_zones = var.availability_zones != null ? var.availability_zones : [
    "${var.region}a",
    "${var.region}b",
    "${var.region}c"
  ]

  # 3 public and 3 private subnets, each with /22 CIDR (1024 IPs per subnet)
  # For 10.0.0.0/16: public = 10.0.0.0/22, 10.0.4.0/22, 10.0.8.0/22; private = 10.0.12.0/22, 10.0.16.0/22, 10.0.20.0/22
  subnet_count = 3
  # newbits = 6 gives /22 subnets from /16 (2^6 = 64 possible /22 blocks)
  public_subnet_cidrs = [
    for i in range(local.subnet_count) : cidrsubnet(var.vpc_cidr, 6, i)
  ]
  private_subnet_cidrs = [
    for i in range(local.subnet_count) : cidrsubnet(var.vpc_cidr, 6, local.subnet_count + i)
  ]
}

module "vpc" {
  source = "./modules/vpc"

  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = local.availability_zones
  public_subnet_cidrs  = local.public_subnet_cidrs
  private_subnet_cidrs = local.private_subnet_cidrs
  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  tags                 = var.tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name        = var.cluster_name
  cluster_version     = var.cluster_version
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  node_group_name     = var.eks.node_group_name
  node_instance_types = var.eks.node_instance_types
  node_desired_size   = var.eks.node_desired_size
  node_min_size       = var.eks.node_min_size
  node_max_size       = var.eks.node_max_size
  node_disk_size      = var.eks.node_disk_size
  ssh_key_name        = var.eks.ssh_key_name
  tags                = var.tags
  depends_on          = [module.vpc]
}

module "aws_lb_controller" {
  count  = var.enable_aws_lb_controller ? 1 : 0
  source = "./modules/aws-lb-controller"

  cluster_name      = var.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  tags              = var.tags

  depends_on = [module.eks]
}

resource "random_password" "opensearch" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "random_password" "mq" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "aws_secretsmanager_secret" "plane_password" {
  name                    = "${var.cluster_name}/plane-password"
  description             = "Plane infrastructure passwords (OpenSearch, MQ)"
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-plane-password"
  })
}

resource "aws_secretsmanager_secret_version" "plane_password" {
  secret_id = aws_secretsmanager_secret.plane_password.id
  secret_string = jsonencode({
    opensearch_password = random_password.opensearch.result
    mq_password         = random_password.mq.result
  })

  depends_on = [aws_secretsmanager_secret.plane_password]
}

module "cache" {
  source = "./modules/cache"

  cluster_id         = var.cluster_name
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = var.vpc_cidr
  subnet_ids         = module.vpc.private_subnet_ids
  node_type          = var.cache.node_type
  num_cache_clusters = var.cache.num_nodes
  engine_version     = var.cache.engine_version
  tags               = var.tags

  depends_on = [module.vpc]
}

module "mq" {
  source = "./modules/mq"

  cluster_name               = var.cluster_name
  vpc_id                     = module.vpc.vpc_id
  vpc_cidr                   = var.vpc_cidr
  subnet_ids                 = [module.vpc.private_subnet_ids[0]]
  mq_username                = var.mq.mq_username
  mq_password                = random_password.mq.result
  allowed_security_group_ids = [module.eks.node_security_group_id]
  engine_version             = var.mq.engine_version
  instance_type              = var.mq.instance_type
  deployment_mode            = var.mq.deployment_mode
  tags                       = var.tags

  depends_on = [module.vpc, aws_secretsmanager_secret_version.plane_password]
}

module "opensearch" {
  source = "./modules/opensearch"

  domain_name     = "${var.cluster_name}-search"
  master_username = var.opensearch.master_username
  master_password = random_password.opensearch.result
  engine_version  = var.opensearch.engine_version
  instance_type   = var.opensearch.instance_type
  instance_count  = var.opensearch.instance_count
  ebs_volume_size = var.opensearch.ebs_volume_size
  tags            = var.tags

  depends_on = [aws_secretsmanager_secret_version.plane_password]
}

module "object_store" {
  source = "./modules/object_store"

  bucket_name_prefix  = var.object_store.bucket_name_prefix
  vpc_id              = module.vpc.vpc_id
  route_table_ids     = module.vpc.private_route_table_ids
  enable_versioning   = var.object_store.enable_versioning
  enable_vpc_endpoint = var.object_store.enable_vpc_endpoint
  tags                = var.tags

  depends_on = [module.vpc]
}

module "rds" {
  source = "./modules/rds"

  cluster_name       = var.cluster_name
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = var.vpc_cidr
  subnet_ids         = module.vpc.private_subnet_ids
  availability_zones = local.availability_zones
  db_name            = var.db.name
  db_username        = var.db.username
  engine_version     = var.db.engine_version
  instance_class     = var.db.instance_class
  allocated_storage  = var.db.allocated_storage
  storage_type       = var.db.storage_type
  iops               = var.db.iops
  tags               = var.tags

  depends_on = [module.vpc]
}
