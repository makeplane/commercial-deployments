output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ. Released only after the NAT gateway and routes exist, so nodes can pull images on first boot."
  value       = module.vpc.private_subnets
  depends_on  = [module.vpc]
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per AZ."
  value       = module.vpc.public_subnets
}
