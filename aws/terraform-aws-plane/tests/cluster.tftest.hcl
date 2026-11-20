# The node image: never AWS's newest release on its own, only the release set in node_group.ami_release_version.
# Runs the cluster module on its own with mock providers.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:user/test" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
  mock_data "aws_iam_session_context" {
    defaults = { issuer_arn = "arn:aws:iam::123456789012:user/test" }
  }
}
mock_provider "time" {}
mock_provider "tls" {}
mock_provider "null" {}
mock_provider "cloudinit" {}

variables {
  name                         = "plane-test"
  kubernetes_version           = "1.36"
  vpc_id                       = "vpc-0123456789abcdef0"
  private_subnet_ids           = ["subnet-0a", "subnet-0b", "subnet-0c"]
  public_access_cidrs          = ["0.0.0.0/0"]
  cluster_admin_principal_arns = []
  node_group = {
    instance_types      = ["m7a.xlarge"]
    min_size            = 2
    max_size            = 4
    desired_size        = 2
    disk_size_gb        = 50
    ami_release_version = null
  }
  addon_versions = {
    vpc_cni                = null
    coredns                = null
    kube_proxy             = null
    eks_pod_identity_agent = null
    aws_ebs_csi_driver     = null
  }
  tags = {}
}

run "node_image_kept_by_default" {
  command = plan
  module {
    source = "./modules/cluster"
  }

  assert {
    condition     = local.node_image.use_latest_ami_release_version == false
    error_message = "The node group must not follow AWS's newest node image on every plan."
  }
  assert {
    condition     = local.node_image.ami_release_version == null
    error_message = "With no release set, the node group must keep its current release."
  }
}

run "node_image_release_passed_through" {
  command = plan
  module {
    source = "./modules/cluster"
  }
  variables {
    node_group = {
      instance_types      = ["m7a.xlarge"]
      min_size            = 2
      max_size            = 4
      desired_size        = 2
      disk_size_gb        = 50
      ami_release_version = "1.36.5-20261119"
    }
  }

  assert {
    condition     = local.node_image.ami_release_version == "1.36.5-20261119" && local.node_image.use_latest_ami_release_version == false
    error_message = "A set node_group.ami_release_version must reach the node group, with the newest-release lookup still off."
  }
}
