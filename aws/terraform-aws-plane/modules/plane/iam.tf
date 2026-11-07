# Plane's pods reach S3 (and OpenSearch and Bedrock, when enabled) through EKS Pod Identity: no access keys
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
    ] : [], slice([
      {
        # pi's migrator assumes the connector role to create the embeddings connector.
        sid       = "PlaneAIEmbeddingsSetup"
        actions   = ["sts:AssumeRole", "sts:TagSession"]
        resources = [one(aws_iam_role.pi_connector[*].arn)]
      },
      {
        sid       = "PlaneAIChatProfile"
        actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        resources = try(local.pi_profile_arns.chat, [])
      },
      {
        # The profile's models, in any region it routes to, only when called through the profile.
        sid       = "PlaneAIChatModels"
        actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        resources = ["arn:${data.aws_partition.current.partition}:bedrock:*::foundation-model/*"]
        condition = [{ test = "StringEquals", variable = "bedrock:InferenceProfileArn", values = try(local.pi_profile_arns.chat, []) }]
      },
  ], 0, local.pi_bedrock ? 3 : 0))

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

  dynamic "statement" {
    for_each = local.pi_bedrock ? [1] : []
    content {
      sid       = "PlaneAIEmbeddingsSetup"
      actions   = ["es:ESHttpPost", "es:ESHttpPut"]
      resources = ["${var.data.opensearch_domain_arn}/*"]

      principals {
        type        = "AWS"
        identifiers = [aws_iam_role.pi_connector[0].arn]
      }
    }
  }
}

resource "aws_opensearch_domain_policy" "plane" {
  count = var.data.opensearch_enabled ? 1 : 0

  domain_name     = var.data.opensearch_domain_name
  access_policies = data.aws_iam_policy_document.opensearch[0].json
}

# Plane AI on Amazon Bedrock: one application inference profile per model (cost tracking by tag, and
# the profile ARN pi needs). A model ID with a geography prefix is a cross-Region inference profile.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  pi_model_sources = local.pi_bedrock ? {
    for k, id in { embeddings = var.pi.bedrock.embedding_model_id, chat = var.pi.bedrock.chat_model_id } :
    k => can(regex("^(us|us-gov|eu|apac|au|jp|ca|in|global)\\.", id)) ? (
      "arn:${data.aws_partition.current.partition}:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/${id}"
    ) : "arn:${data.aws_partition.current.partition}:bedrock:${var.region}::foundation-model/${id}"
  } : {}

  # What may be invoked for each model: the module's profile and the cross-Region profile it copies.
  pi_profile_arns = {
    for k, source in local.pi_model_sources :
    k => concat([aws_bedrock_inference_profile.pi[k].arn], strcontains(source, ":inference-profile/") ? [source] : [])
  }
}

resource "aws_bedrock_inference_profile" "pi" {
  for_each = local.pi_model_sources

  name        = "${var.name}-pi-${each.key}"
  description = "Plane AI (${var.name}) ${each.key}"

  model_source {
    copy_from = each.value
  }

  tags = var.tags
}

# OpenSearch assumes this role to call the embeddings profile; pi's migrator assumes it to create the
# connector (it signs with the role it passes). No fine-grained access control: IAM authorizes ML APIs.
data "aws_iam_policy_document" "pi_connector_trust" {
  count = local.pi_bedrock ? 1 : 0

  statement {
    sid     = "OpenSearch"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["opensearchservice.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [var.data.opensearch_domain_arn]
    }
  }

  # Pod Identity's session tags are transitive, so chaining into this role needs sts:TagSession.
  statement {
    sid     = "PlaneAI"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "AWS"
      identifiers = [module.plane_pod_identity.iam_role_arn]
    }
  }
}

resource "aws_iam_role" "pi_connector" {
  count = local.pi_bedrock ? 1 : 0

  name               = "${var.name}-pi-embeddings"
  description        = "Plane AI (${var.name}): OpenSearch calls the Bedrock embedding model"
  assume_role_policy = data.aws_iam_policy_document.pi_connector_trust[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "pi_connector" {
  count = local.pi_bedrock ? 1 : 0

  statement {
    sid       = "EmbeddingProfile"
    actions   = ["bedrock:InvokeModel"]
    resources = local.pi_profile_arns.embeddings
  }

  # The profile's model, in any region it routes to, only when called through the profile.
  statement {
    sid       = "EmbeddingModel"
    actions   = ["bedrock:InvokeModel"]
    resources = ["arn:${data.aws_partition.current.partition}:bedrock:*::foundation-model/*"]

    condition {
      test     = "StringEquals"
      variable = "bedrock:InferenceProfileArn"
      values   = local.pi_profile_arns.embeddings
    }
  }

  statement {
    sid       = "ConnectorSetup"
    actions   = ["es:ESHttpPost", "es:ESHttpPut"]
    resources = ["${var.data.opensearch_domain_arn}/*"]
  }

  statement {
    sid       = "PassToOpenSearch"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.pi_connector[0].arn]
  }
}

resource "aws_iam_role_policy" "pi_connector" {
  count = local.pi_bedrock ? 1 : 0

  name   = "bedrock-embeddings"
  role   = aws_iam_role.pi_connector[0].id
  policy = data.aws_iam_policy_document.pi_connector[0].json
}
