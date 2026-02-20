output "role_arn" {
  description = "ARN of the IAM role for the AWS Load Balancer Controller (use in ServiceAccount annotation)"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the IAM role for the AWS Load Balancer Controller"
  value       = aws_iam_role.this.name
}

output "policy_arn" {
  description = "ARN of the IAM policy attached to the AWS Load Balancer Controller role"
  value       = aws_iam_policy.this.arn
}
