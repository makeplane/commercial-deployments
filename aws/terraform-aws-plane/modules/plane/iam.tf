# Plane's pods reach S3 (and OpenSearch, when enabled) through EKS Pod Identity: no access keys
# anywhere. The chart's
# ServiceAccount is "<release>-srv-account"; Pod Identity binds to it by name.

module "plane_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name                 = "${var.name}-plane"
  attach_custom_policy = true

  policy_statements = concat([
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
    ], var.data.opensearch_enabled ? [
    {
      sid       = "Search"
      actions   = ["es:ESHttpGet", "es:ESHttpHead", "es:ESHttpPost", "es:ESHttpPut", "es:ESHttpPatch", "es:ESHttpDelete"]
      resources = ["${var.data.opensearch_domain_arn}/*"]
    },
  ] : [])

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = local.namespace
      service_account = local.service_account
    }
  }

  tags = var.tags
}

# OpenSearch accepts Plane's role (SigV4) and nothing else through its domain policy.
data "aws_iam_policy_document" "opensearch" {
  count = var.data.opensearch_enabled ? 1 : 0

  statement {
    sid       = "PlaneSearch"
    actions   = ["es:ESHttp*"]
    resources = ["${var.data.opensearch_domain_arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [module.plane_pod_identity.iam_role_arn]
    }
  }
}

resource "aws_opensearch_domain_policy" "plane" {
  count = var.data.opensearch_enabled ? 1 : 0

  domain_name     = var.data.opensearch_domain_name
  access_policies = data.aws_iam_policy_document.opensearch[0].json
}
