# Pod Identity roles for the add-ons, each scoped to what that add-on touches.

module "lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name                            = "${var.name}-aws-lbc"
  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "kube-system"
      service_account = local.lb_controller_sa
    }
  }

  tags = var.tags
}

module "external_secrets_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name                                  = "${var.name}-external-secrets"
  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = concat(values(var.secret_arns), var.certificate_secret_arns)
  external_secrets_kms_key_arns         = [var.kms_key_arn]
  external_secrets_create_permission    = false

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = local.external_secrets_namespace
      service_account = local.external_secrets_sa
    }
  }

  tags = var.tags
}
