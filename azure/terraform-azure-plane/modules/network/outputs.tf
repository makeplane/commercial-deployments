output "vnet_id" {
  description = "VNet ID."
  value       = azurerm_virtual_network.this.id
}

output "aks_subnet_id" {
  description = "AKS node subnet ID. Released only after the NAT gateway is attached (outbound_type = userAssignedNATGateway needs it before the cluster), so nodes can pull images on first boot."
  value       = azurerm_subnet.aks.id
  depends_on  = [azurerm_subnet_nat_gateway_association.aks, azurerm_nat_gateway_public_ip_association.this]
}

output "postgres_subnet_id" {
  description = "Subnet delegated to PostgreSQL Flexible Server."
  value       = azurerm_subnet.postgres.id
}

output "private_endpoints_subnet_id" {
  description = "Subnet for private endpoints."
  value       = azurerm_subnet.private_endpoints.id
}

output "nat_public_ip" {
  description = "Egress public IP of the nodes (NAT gateway)."
  value       = azurerm_public_ip.nat.ip_address
}
