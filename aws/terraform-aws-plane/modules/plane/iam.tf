# Plane's pods reach S3 through EKS Pod Identity: no access keys anywhere. The chart's
# ServiceAccount is "<release>-srv-account"; Pod Identity binds to it by name.

module "plane_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name                 = "${var.name}-plane"
  attach_custom_policy = true

  policy_statements = [
    {
      sid       = "UploadsBucket"
      actions   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
      resources = [var.data.bucket_arn]
    },
    {
      sid = "UploadsObjects"
      actions = [
        "s3:GetObject",
        "s3:GetObjectAttributes",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts",
      ]
      resources = ["${var.data.bucket_arn}/*"]
    },
    {
      sid       = "UploadsEncryption"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [var.data.kms_key_arn]
    },
  ]

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = local.namespace
      service_account = local.service_account
    }
  }

  tags = var.tags
}
