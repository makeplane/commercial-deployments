output "nlb_arn" {
  description = "ARN of the email NLB"
  value       = aws_lb.email.arn
}

output "nlb_dns_name" {
  description = "DNS name of the email NLB — use as MX record target"
  value       = aws_lb.email.dns_name
}

output "nlb_zone_id" {
  description = "Route53 hosted zone ID of the NLB — use for alias records"
  value       = aws_lb.email.zone_id
}

output "target_group_arns" {
  description = "Target group ARNs keyed by port name (smtp, smtps, submission)"
  value = {
    smtp       = aws_lb_target_group.smtp.arn
    smtps      = aws_lb_target_group.smtps.arn
    submission = aws_lb_target_group.submission.arn
  }
}
