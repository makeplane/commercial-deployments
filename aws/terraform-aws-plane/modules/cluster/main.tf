locals {
  admin_access_entries = {
    for i, arn in var.cluster_admin_principal_arns : "admin-${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # A null version means "most recent for kubernetes_version".
  addon_version = {
    "vpc-cni"                = var.addon_versions.vpc_cni
    "coredns"                = var.addon_versions.coredns
    "kube-proxy"             = var.addon_versions.kube_proxy
    "eks-pod-identity-agent" = var.addon_versions.eks_pod_identity_agent
    "aws-ebs-csi-driver"     = var.addon_versions.aws_ebs_csi_driver
  }
}

# EBS CSI driver identity. No Plane workload needs a volume by default (all data is external),
# but the driver keeps the optional in-cluster RabbitMQ and future stateful workloads working.
module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name                      = "${var.name}-ebs-csi"
  attach_aws_ebs_csi_policy = true

  tags = var.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Public endpoint as today's module (restrict with cluster_endpoint_public_access_cidrs); the private
  # endpoint is always on so nodes talk to the API inside the VPC.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.public_access_cidrs
  endpoint_private_access      = true

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true
  access_entries                           = local.admin_access_entries

  enabled_log_types = ["api", "audit", "authenticator"]

  addons = {
    vpc-cni = {
      addon_version  = local.addon_version["vpc-cni"]
      most_recent    = local.addon_version["vpc-cni"] == null
      before_compute = true
    }
    eks-pod-identity-agent = {
      addon_version  = local.addon_version["eks-pod-identity-agent"]
      most_recent    = local.addon_version["eks-pod-identity-agent"] == null
      before_compute = true
    }
    kube-proxy = {
      addon_version = local.addon_version["kube-proxy"]
      most_recent   = local.addon_version["kube-proxy"] == null
    }
    coredns = {
      addon_version = local.addon_version["coredns"]
      most_recent   = local.addon_version["coredns"] == null
    }
    aws-ebs-csi-driver = {
      addon_version = local.addon_version["aws-ebs-csi-driver"]
      most_recent   = local.addon_version["aws-ebs-csi-driver"] == null
      # The add-on schema only offers defaultStorageClass.enabled (no custom classes).
      configuration_values = jsonencode({ defaultStorageClass = { enabled = true } })
      pod_identity_association = [{
        role_arn        = module.ebs_csi_pod_identity.iam_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  # min..max range as today (2..4); no autoscaler yet. The EKS module ignores desired_size after creation, so a
  # manual (or future autoscaler) scale-out isn't reverted by the next apply.
  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_group.instance_types
      min_size       = var.node_group.min_size
      max_size       = var.node_group.max_size
      desired_size   = var.node_group.desired_size
      subnet_ids     = var.private_subnet_ids

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.node_group.disk_size_gb
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      # Replace one node at a time during node-group upgrades.
      update_config = {
        max_unavailable = 1
      }
    }
  }

  tags = var.tags
}
