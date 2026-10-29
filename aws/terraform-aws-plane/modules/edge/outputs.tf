output "eip_allocation_ids" {
  description = "EIP allocation IDs for the NLB annotation."
  value       = aws_eip.lb[*].allocation_id
}

output "public_ips" {
  description = "Public IPs of the load balancer."
  value       = aws_eip.lb[*].public_ip
}
