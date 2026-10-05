output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "aks_subnet_id" {
  description = "ID of the AKS node subnet"
  value       = azurerm_subnet.aks.id
}

output "postgres_subnet_id" {
  description = "ID of the delegated PostgreSQL subnet"
  value       = azurerm_subnet.postgres.id
}

output "private_endpoints_subnet_id" {
  description = "ID of the private endpoints subnet"
  value       = azurerm_subnet.private_endpoints.id
}

output "nat_public_ip" {
  description = "Egress public IP of the AKS nodes (NAT gateway)"
  value       = azurerm_public_ip.nat.ip_address
}

output "nat_gateway_association_id" {
  description = "ID of the NAT gateway to AKS subnet association (AKS must be created after it)"
  value       = azurerm_subnet_nat_gateway_association.aks.id
}
