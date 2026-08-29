variable "domain_name" {
  description = "OpenSearch domain name"
  type        = string
}

variable "enable_vpc" {
  description = "Whether to place the OpenSearch domain in a VPC (required for Bedrock connector integration)."
  type        = bool
  default     = false

  validation {
    condition = (
      var.enable_vpc == false ||
      (var.vpc_id != null && var.subnet_ids != null && length(var.subnet_ids) > 0)
    )
    error_message = "When enable_vpc is true, you must provide vpc_id and a non-empty subnet_ids list."
  }
}

variable "vpc_id" {
  description = "VPC ID for the OpenSearch domain security group (required when enable_vpc = true)."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnet IDs for the OpenSearch domain VPC options (required when enable_vpc = true)."
  type        = list(string)
  default     = null
}

variable "master_username" {
  description = "OpenSearch master username for fine-grained access control"
  type        = string
}

variable "master_password" {
  description = "OpenSearch master password"
  type        = string
  sensitive   = true
}

variable "engine_version" {
  description = "OpenSearch engine version"
  type        = string
  default     = "OpenSearch_2.19"
}

variable "instance_type" {
  description = "OpenSearch instance type"
  type        = string
  default     = "t3.small.search"
}

variable "instance_count" {
  description = "Number of instances"
  type        = number
  default     = 2
}

variable "ebs_volume_size" {
  description = "EBS volume size in GB"
  type        = number
  default     = 10
}

variable "ebs_volume_type" {
  description = "EBS volume type"
  type        = string
  default     = "gp3"
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

variable "create_connector" {
  description = "When true, deploy the Bedrock connector/model integration CloudFormation stack and output connector/model IDs."
  type        = bool
  default     = false

  validation {
    condition = (
      var.create_connector == false ||
      (var.enable_vpc &&
        var.vpc_id != null &&
        var.subnet_ids != null &&
        length(var.subnet_ids) > 0 &&
        var.bedrock_model_region != null &&
        var.bedrock_model != null &&
        var.bedrock_model_name != null
      )
    )
    error_message = "When create_connector is true, enable_vpc must be true and you must set vpc_id, a non-empty subnet_ids list, bedrock_model_region, bedrock_model, and bedrock_model_name."
  }
}

variable "bedrock_model_region" {
  description = "Bedrock model region (CloudFormation parameter: BedrockModelRegion). Required when create_connector = true."
  type        = string
  default     = null
}

variable "bedrock_model" {
  description = "Bedrock model ID (CloudFormation parameter: Model). Required when create_connector = true."
  type        = string
  default     = null
}

variable "bedrock_model_name" {
  description = "A name used to tag/namescope created integration resources (CloudFormation parameter: ModelName). Required when create_connector = true."
  type        = string
  default     = null
}

variable "add_process_function" {
  description = "Enable the default pre/post processing functions in the connector (CloudFormation parameter: AddProcessFunction)."
  type        = bool
  default     = true
}

variable "add_offline_batch_inference" {
  description = "Enable the bath_predict action in the connector (CloudFormation parameter: AddOfflineBatchInference)."
  type        = bool
  default     = false
}

variable "lambda_invoke_opensearch_mlcommons_role_name" {
  description = "IAM role name used by Lambda to invoke OpenSearch (CloudFormation parameter: LambdaInvokeOpenSearchMLCommonsRoleName)."
  type        = string
  default     = "LambdaInvokeOpenSearchMLCommonsRole"
}

variable "connector_subnet_ids" {
  description = "Subnet IDs for the connector Lambda VPC config. Defaults to subnet_ids when null."
  type        = list(string)
  default     = null
}

variable "connector_security_group_ids" {
  description = "Security group IDs for the connector Lambda VPC config. Defaults to the module-created OpenSearch SG when null."
  type        = list(string)
  default     = null
}

variable "allowed_ingress_security_group_ids" {
  description = "Optional additional security group IDs allowed to reach OpenSearch over HTTPS (443) when VPC-enabled (e.g., EKS node SG)."
  type        = list(string)
  default     = []
}
