mock_provider "azurerm" {
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/plane-test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock"
      client_id    = "00000000-0000-0000-0000-00000000000c"
      principal_id = "00000000-0000-0000-0000-00000000000a"
    }
  }
}
mock_provider "time" {}

variables {
  name                            = "plane-test"
  location                        = "eastus2"
  resource_group_name             = "plane-test-rg"
  resource_group_id               = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/plane-test-rg"
  subnet_id                       = "/subscriptions/mock/resourceGroups/plane-test-rg/providers/Microsoft.Network/virtualNetworks/plane-test-vnet/subnets/aks"
  zones                           = ["1", "2", "3"]
  kubernetes_version              = "1.36"
  api_server_authorized_ip_ranges = []
  nat_public_ip                   = "20.0.0.1"
  tenant_id                       = "00000000-0000-0000-0000-000000000001"
  deployer_object_id              = "00000000-0000-0000-0000-000000000002"
  cluster_admin_object_ids        = []
  node_pool                       = { vm_size = "Standard_D4ds_v5", min_count = 2, max_count = 4, node_count = 2, os_disk_size_gb = 128, sku_tier = "Standard" }
  pod_cidr                        = "192.168.0.0/16"
  service_cidr                    = "172.16.0.0/16"
  dns_service_ip                  = "172.16.0.10"
  tags                            = {}
}

run "api_server_open_by_default" {
  command = plan
  module {
    source = "./modules/cluster"
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.api_server_access_profile) == 0
    error_message = "With no api_server_authorized_ip_ranges the API server must stay unrestricted (no NAT IP added)."
  }
}

run "api_server_restricted_adds_nat_ip" {
  command = plan
  module {
    source = "./modules/cluster"
  }
  variables {
    api_server_authorized_ip_ranges = ["203.0.113.0/24"]
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.api_server_access_profile[0].authorized_ip_ranges == toset(["203.0.113.0/24", "20.0.0.1/32"])
    error_message = "A restricted API server must also allow the nodes' NAT egress IP (AKS adds only load balancer outbound IPs)."
  }
}

run "api_server_nat_ip_listed_once" {
  command = plan
  module {
    source = "./modules/cluster"
  }
  variables {
    api_server_authorized_ip_ranges = ["203.0.113.0/24", "20.0.0.1/32"]
  }

  assert {
    condition     = length([for r in azurerm_kubernetes_cluster.this.api_server_access_profile[0].authorized_ip_ranges : r if r == "20.0.0.1/32"]) == 1 && length(azurerm_kubernetes_cluster.this.api_server_access_profile[0].authorized_ip_ranges) == 2
    error_message = "The NAT IP must appear once when the user already lists it."
  }
}
