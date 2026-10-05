# Plane Azure Terraform Module

A Terraform module that provisions Azure infrastructure for running [Plane](https://plane.so). It deploys:
- a VNet with a NAT gateway
- AKS (Workload Identity, Entra ID + Azure RBAC)
- PostgreSQL Flexible Server
- Azure Managed Redis
- a Blob storage account
- a Key Vault with generated credentials
- workload identities
- static public IPs for ingress and email

For the step-by-step deployment guide, including the Helm install, see [../README.md](../README.md).

## Prerequisites

- **Terraform** >= 1.5 and the **azurerm** provider `~> 5.8`
- **Azure CLI**, logged in (`az login`)
- **Owner** on the subscription, or **Contributor + User Access Administrator**. The module creates role assignments.
- The resource providers `Microsoft.ContainerService`, `Microsoft.DBforPostgreSQL`, `Microsoft.Cache`, `Microsoft.Storage`, `Microsoft.KeyVault`, `Microsoft.Network` and `Microsoft.ManagedIdentity` registered on the subscription
- Enough regional vCPU quota for the node pools (20 vCPUs of `DDSv5` with the defaults)

## Architecture

```
                    Internet
          ┌─────────────┴─────────────┐
   ingress public IP           email public IP (optional)
          │                           │
┌─────────┴───────────────────────────┴──────────────── VNet 10.0.0.0/16 ┐
│  aks-nodes 10.0.0.0/20  ──► NAT gateway ──► egress IP                   │
│    system pool (critical add-ons only)                                 │
│    plane pool: Plane, Traefik, RabbitMQ, OpenSearch, MinIO             │
│  postgres 10.0.16.0/24 (delegated) ── PostgreSQL Flexible Server        │
│  private-endpoints 10.0.17.0/24 ── Managed Redis, Blob (, Key Vault)   │
└────────────────────────────────────────────────────────────────────────┘
```

- **Private data plane:** PostgreSQL, Redis and Blob storage have no public endpoint. They resolve to private IPs inside the VNet through private DNS zones.
- **Overlay networking:** pods use `192.168.0.0/16` and Services use `172.16.0.0/16` (Azure CNI Overlay + Cilium), so neither consumes VNet addresses.
- **Fixed egress:** all outbound traffic leaves through the NAT gateway's public IP (`nat_public_ip`).
- **No static credentials in pods for Azure services:** Plane pods reach Blob storage through Workload Identity. External Secrets Operator reads Key Vault the same way.

### AWS to Azure mapping

| Plane needs | AWS module ([../../terraform](../../terraform)) | This module |
|---|---|---|
| Kubernetes | EKS + managed node group | AKS: system and user pools across zones 1-3 |
| PostgreSQL | RDS Multi-AZ cluster | PostgreSQL Flexible Server: VNet-integrated, zone-redundant HA |
| Redis | ElastiCache | Azure Managed Redis: private endpoint, TLS on port 10000 |
| Object storage | S3 + VPC endpoint | Storage account (ZRS) + container: private endpoint, Entra ID auth only |
| RabbitMQ | Amazon MQ | Not provisioned; runs in-cluster. Azure has no managed AMQP 0-9-1 broker. |
| OpenSearch | Amazon OpenSearch | Not provisioned; runs in-cluster. Azure has no managed OpenSearch. |
| Secrets | Secrets Manager | Key Vault (RBAC mode) |
| Pod → cloud auth | IRSA | Workload Identity (user-assigned identities + federated credentials) |
| Ingress | ALB controller IAM role | Static public IP for the ingress controller's LoadBalancer Service |
| Inbound email | NLB → NodePorts (two-stage apply) | Static public IP for the email LoadBalancer Service (single stage) |
| Block storage | EBS CSI add-on | Built into AKS (`managed-csi-premium`) |

## Usage

```hcl
module "plane_infra" {
  source = "git::https://github.com/makeplane/commercial-deployments.git//azure/terraform?ref=main"

  name     = "plane-aks"
  location = "eastus2"

  tags = {
    Environment = "plane"
  }
}
```

The [examples/](examples/) directory is a complete configuration that passes every input through:

```bash
cd examples
cp terraform.tfvars.example terraform.tfvars   # edit
terraform init
terraform plan
terraform apply
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `location` | `string` | — (**required**) | Azure region. It must support availability zones. |
| `name` | `string` | `"plane-aks"` | Prefix for every resource and the AKS cluster name. 3-32 chars: lowercase letters, digits and hyphens. |
| `subscription_id` | `string` | `null` | Subscription to deploy into. `null` uses `ARM_SUBSCRIPTION_ID` or the Azure CLI default. |
| `create_resource_group` | `bool` | `true` | `false` deploys into an existing resource group. |
| `resource_group_name` | `string` | `null` | Resource group name. `null` means `<name>-rg`. |
| `zones` | `list(string)` | `["1","2","3"]` | Zones for the node pools, NAT and public IPs. |
| `vnet_cidr` | `string` | `"10.0.0.0/16"` | VNet address space. A /20 goes to AKS nodes, a /24 to PostgreSQL and a /24 to private endpoints. |
| `kubernetes_version` | `string` | `null` | AKS version as `major.minor`. `null` means the AKS default. |
| `aks` | `object` | see below | Cluster and node pools. |
| `postgres` | `object` | see below | PostgreSQL Flexible Server. |
| `redis` | `object` | see below | Azure Managed Redis. |
| `object_store` | `object` | see below | Blob storage account. |
| `key_vault` | `object` | see below | Key Vault. |
| `plane_namespace` | `string` | `"plane"` | Namespace Plane is installed into. The workload identities trust ServiceAccounts in this namespace. |
| `plane_service_account` | `string` | `"plane-srv-account"` | ServiceAccount of the Plane pods. The plane-enterprise chart names it `<release>-srv-account`. |
| `eso_service_account` | `string` | `"plane-keyvault-reader"` | ServiceAccount the Key Vault SecretStore authenticates as (in `plane_namespace`). |
| `ingress_domain_name_label` | `string` | `null` | Optional label that makes `<label>.<location>.cloudapp.azure.com` resolve to the ingress IP. |
| `enable_email_public_ip` | `bool` | `false` | Create a static public IP for inbound email. |
| `tags` | `map(string)` | `{}` | Tags for every resource. |

### `aks`

| Field | Default | Description |
|---|---|---|
| `sku_tier` | `"Standard"` | `Free`, `Standard` (uptime SLA) or `Premium`. |
| `system_node_vm_size` | `"Standard_D4ds_v5"` | System pool VM size. This pool runs critical add-ons only. |
| `system_node_min_count` / `system_node_max_count` | `2` / `3` | System pool autoscaling range. |
| `workload_node_pool_name` | `"plane"` | User pool name: lowercase alphanumeric, up to 12 chars. |
| `workload_node_vm_size` | `"Standard_D4ds_v5"` | User pool VM size. This pool runs Plane. |
| `workload_node_min_count` / `workload_node_max_count` | `3` / `6` | User pool autoscaling range. |
| `node_os_disk_size_gb` | `128` | OS disk size for every node. |
| `admin_group_object_ids` | `[]` | Entra ID groups granted cluster-admin. |
| `api_server_authorized_ip_ranges` | `[]` | CIDRs allowed to reach the API server. Empty means unrestricted. |
| `local_account_disabled` | `true` | Disables the static admin kubeconfig, so all access goes through Entra ID. |
| `pod_cidr` | `"192.168.0.0/16"` | Overlay pod CIDR. It must not overlap the VNet. |
| `service_cidr` / `dns_service_ip` | `"172.16.0.0/16"` / `"172.16.0.10"` | Service CIDR and cluster DNS IP. |

### `postgres`

| Field | Default | Description |
|---|---|---|
| `engine_version` | `"16"` | PostgreSQL major version. |
| `sku_name` | `"GP_Standard_D4ds_v5"` | Compute SKU. Burstable (`B_*`) SKUs require `high_availability_mode = "Disabled"`. |
| `storage_mb` | `131072` | Initial storage. Auto-grow is enabled. |
| `high_availability_mode` | `"ZoneRedundant"` | `ZoneRedundant`, `SameZone` or `Disabled`. |
| `backup_retention_days` | `14` | Point-in-time restore window, 7-35 days. |
| `geo_redundant_backup_enabled` | `false` | Keep backups in the paired region. This can only be set at creation. |
| `administrator_login` | `"planeadmin"` | Admin username. The password is generated and stored in Key Vault. |
| `database_names` | `["plane", "plane_pi"]` | Databases to create. The first is Plane's; the second is Plane AI's. |

### `redis`

| Field | Default | Description |
|---|---|---|
| `sku_name` | `"Balanced_B1"` | Azure Managed Redis SKU. |
| `high_availability_enabled` | `true` | Replicate to a second node. |
| `clustering_policy` | `"NoCluster"` | `NoCluster` or `EnterpriseCluster`. Plane's clients are not cluster-aware, so `OSSCluster` is rejected. |

### `object_store`

| Field | Default | Description |
|---|---|---|
| `account_name_prefix` | `"plane"` | Storage account name prefix. A random suffix is appended. |
| `replication_type` | `"ZRS"` | `LRS`, `ZRS`, `GRS`, `RAGRS`, `GZRS` or `RAGZRS`. |
| `container_name` | `"uploads"` | Container for Plane uploads. |
| `versioning_enabled` | `false` | Keep previous versions of overwritten blobs. |
| `soft_delete_retention_days` | `7` | Days deleted blobs and containers can be recovered. |
| `public_network_access_enabled` | `false` | Expose the Blob endpoint publicly. Leave this off: Plane proxies storage traffic through its API. |

### `key_vault`

| Field | Default | Description |
|---|---|---|
| `allowed_ips` | `[]` | Firewall allow-list. Empty means no firewall (still RBAC-gated). When set, include the IP you run Terraform from; the cluster's NAT IP is added automatically. |
| `public_network_access_enabled` | `true` | Serve the vault on its public endpoint, subject to `allowed_ips`. |
| `private_endpoint_enabled` | `false` | Add a private endpoint. Terraform must then run inside the VNet if public access is off. |
| `purge_protection_enabled` | `true` | Block permanent deletion during the retention period. |
| `soft_delete_retention_days` | `30` | Recovery window, 7-90 days. |

## What Gets Created

| Resource | Name | Notes |
|---|---|---|
| Resource group | `<name>-rg` | Skipped with `create_resource_group = false` |
| VNet, 3 subnets, NAT gateway + public IP | `<name>-vnet`, … | The PostgreSQL subnet is delegated to Flexible Server |
| AKS cluster + `plane` node pool | `<name>` | Node resource group `<rg>-<name>-nodes`. The control plane identity has *Network Contributor* on the resource group, so it can attach the static IPs. |
| PostgreSQL Flexible Server | `<name>-<suffix>-postgres` | Private DNS zone `<name>-<suffix>-postgres.private.postgres.database.azure.com`. Maintenance window: Monday 04:00 UTC. |
| Azure Managed Redis | `<name>-<suffix>-redis` | Private endpoint + `privatelink.redis.azure.net` |
| Storage account + container | `plane<suffix>` / `uploads` | Private endpoint + `privatelink.blob.core.windows.net`. Shared-key auth is disabled. |
| Key Vault | `<name>-kv-<suffix>` | RBAC mode. Holds the secrets below. |
| Managed identity | `<name>-plane-workload` | Trusts `system:serviceaccount:<plane_namespace>:<plane_service_account>`. Has *Storage Blob Data Contributor* on the storage account. |
| Managed identity | `<name>-external-secrets` | Trusts `system:serviceaccount:<plane_namespace>:<eso_service_account>`. Has *Key Vault Secrets User* on the vault. |
| Managed identity | `<name>-aks-control-plane` | AKS control plane identity |
| Public IPs | `<name>-ingress-pip`, `<name>-email-pip` | The email IP is created only with `enable_email_public_ip` |

The identity running Terraform is granted *Azure Kubernetes Service RBAC Cluster Admin* on the cluster and *Key Vault Secrets Officer* on the vault.

### Key Vault secrets

Each secret is a JSON document whose keys match the plane-enterprise chart's `external_secrets.*` defaults. External Secrets can therefore mirror them with a plain `dataFrom.extract`.

| Secret | Keys |
|---|---|
| `plane-postgres` | `username`, `password`, `host`, `port`, `dbname` |
| `plane-redis` | `host`, `port`, `password` |
| `plane-rabbitmq` | `username`, `password` (in-cluster RabbitMQ) |
| `plane-opensearch` | `username`, `password` (in-cluster OpenSearch) |
| `plane-minio` | `username`, `password` (in-cluster MinIO, until Plane ships its native Azure Blob provider) |
| `plane-app-keys` | `SECRET_KEY`, `AES_SECRET_KEY`, `LIVE_SERVER_SECRET_KEY`, `PI_INTERNAL_SECRET`, `SILO_HMAC_SECRET_KEY` |

> `SECRET_KEY` and `AES_SECRET_KEY` encrypt data at rest. Never regenerate them for an existing installation. Existing ciphertext becomes unreadable, and nothing reports the failure.

## Outputs

| Category | Outputs |
|---|---|
| Network | `vnet_id`, `aks_subnet_id`, `nat_public_ip` |
| AKS | `aks_cluster_name`, `aks_node_resource_group`, `aks_oidc_issuer_url`, `configure_kubectl` |
| Data stores | `postgres_fqdn`, `postgres_database_names`, `redis_hostname`, `redis_port`, `storage_account_name`, `storage_blob_endpoint`, `storage_container_name` |
| Secrets | `key_vault_name`, `key_vault_uri`, `key_vault_secret_names`, `tenant_id` |
| Identity | `plane_workload_identity_client_id`, `keyvault_reader_identity_client_id` |
| Public IPs | `ingress_public_ip`, `ingress_public_ip_name`, `ingress_fqdn`, `email_public_ip`, `email_public_ip_name` |
| Helm | `helm_values`: a plane-enterprise values fragment (identity, PostgreSQL, Redis, storage class) |
| General | `resource_group_name` |

## Operations

- **State:** Terraform state contains the generated passwords and keys, as it does for the AWS module. Use a remote backend with encryption, such as Azure Storage with `use_azuread_auth`, and restrict who can read it.
- **Upgrades:** AKS uses the `patch` auto-upgrade channel and weekly node-image updates. Change `kubernetes_version` (as `major.minor`) for minor upgrades.
- **Backups:** PostgreSQL keeps point-in-time restore for `backup_retention_days`. Back up the in-cluster MinIO, RabbitMQ and OpenSearch volumes separately, for example with AKS Backup or volume snapshots.
- **Failover:** PostgreSQL may swap its primary and standby zones on failover. The module ignores that drift, so a later apply does not try to move them back.

## Cleanup

Release the static IPs from the cluster's load balancer before destroying. Uninstall Traefik and delete the email Service; otherwise deleting the IPs fails with "in use". Then:

```bash
terraform destroy
```

**Warning:** this permanently deletes all data in PostgreSQL (including its backups), Redis, the storage account and every persistent volume in the cluster.
