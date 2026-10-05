# Plane on Azure

Deploy [Plane](https://plane.so) on Azure Kubernetes Service. This directory provides:

1. **Terraform** ([terraform/](terraform/)): provisions the Azure infrastructure. That means the VNet with a NAT gateway, AKS, PostgreSQL Flexible Server, Azure Managed Redis, Blob storage, Key Vault, workload identities and static public IPs.
2. **Examples** ([examples/](examples/)): wire that infrastructure into the [plane-enterprise Helm chart](https://github.com/makeplane/helm-charts/tree/master/charts/plane-enterprise), with External Secrets Operator reading from Key Vault.

It is the Azure counterpart of the AWS module in [../terraform](../terraform).

## Architecture

| Plane needs | AWS module | This module |
|---|---|---|
| Kubernetes | EKS + managed node group | AKS: system and user pools across zones 1-3, Azure CNI Overlay + Cilium, Entra ID + Azure RBAC |
| PostgreSQL | RDS Multi-AZ cluster | PostgreSQL Flexible Server: VNet-integrated (no public endpoint), zone-redundant HA, databases `plane` and `plane_pi` |
| Redis | ElastiCache | Azure Managed Redis: private endpoint, TLS on port 10000, non-clustered |
| Object storage | S3 + VPC endpoint | Storage account (ZRS) + `uploads` container: private endpoint, Entra ID auth only (no account keys). **Interim:** in-cluster MinIO; see below. |
| RabbitMQ | Amazon MQ | In-cluster (chart `services.rabbitmq.local_setup`). Azure has no managed AMQP 0-9-1 broker; Service Bus speaks AMQP 1.0. |
| OpenSearch | Amazon OpenSearch | In-cluster (chart `services.opensearch.local_setup`). Azure has no managed OpenSearch. |
| Secrets | Secrets Manager | Key Vault (RBAC mode), mirrored into Kubernetes by External Secrets Operator |
| Pod → cloud auth | IRSA | Workload Identity: user-assigned identities with federated credentials |
| Egress | NAT gateway | NAT gateway, giving one stable egress IP |
| Ingress | ALB controller | Traefik on a static public IP |
| Inbound email | NLB → NodePorts, two-stage apply | The email Service's own LoadBalancer on a static public IP, one stage |
| Block storage | EBS CSI add-on | Built into AKS (`managed-csi-premium`) |

```
                    Internet
          ┌─────────────┴─────────────┐
   ingress public IP           email public IP (optional)
          │                           │
┌─────────┴───────────────────────────┴──────────────── VNet 10.0.0.0/16 ┐
│  aks-nodes 10.0.0.0/20  ──► NAT gateway ──► egress IP                   │
│    system pool (critical add-ons)                                      │
│    plane pool: Plane, Traefik, RabbitMQ, OpenSearch                    │
│  postgres 10.0.16.0/24 (delegated) ── Flexible Server                  │
│  private-endpoints 10.0.17.0/24 ── Managed Redis, Blob (, Key Vault)   │
└────────────────────────────────────────────────────────────────────────┘
```

Pods use an overlay CIDR (`192.168.0.0/16`) and Services use `172.16.0.0/16`, so neither consumes VNet addresses.

## Object storage: native Azure Blob

Plane talks to object storage through a provider switch (`STORAGE_PROVIDER`), which supports `S3` and `GCS` today. Azure Blob has no S3 API, so this deployment targets a native `AZURE` provider. It runs in storage-proxy mode (`use_storage_proxy: true`), where uploads and downloads flow through the Plane API. As a result, the storage account needs no public endpoint, CORS rules or SAS tokens.

> **Status:** the `AZURE` storage provider (Plane API, silo and Plane AI, plus the `env.azure_storage_*` chart values) is in progress. Until a release ships it, [examples/values-azure.yaml](examples/values-azure.yaml) deploys the chart's bundled MinIO on a 100 Gi Premium SSD volume. Terraform still creates the storage account, so switching later is a values change; the block to use is at the end of that file. Back up the MinIO volume (for example with AKS backup or volume snapshots), because it holds every upload until then.

## Prerequisites

- **Terraform** >= 1.5
- **Azure CLI**, logged in (`az login`) with Owner, or with Contributor plus User Access Administrator, on the subscription. The module creates role assignments.
- **kubectl**, **kubelogin** (`az aks install-cli`) and **Helm** 3
- Resource providers registered on the subscription:

  ```bash
  for ns in Microsoft.ContainerService Microsoft.DBforPostgreSQL Microsoft.Cache \
            Microsoft.Storage Microsoft.KeyVault Microsoft.Network Microsoft.ManagedIdentity; do
    az provider register --namespace "$ns"
  done
  ```
- A region with availability zones, Azure Managed Redis and zone-redundant PostgreSQL HA. Examples are `eastus2`, `westus3`, `northeurope` and `westeurope`.

## Step 1: Provision the infrastructure

```bash
cd azure/terraform/examples
cp terraform.tfvars.example terraform.tfvars   # edit: location, sizes, key_vault.allowed_ips
export ARM_SUBSCRIPTION_ID=<subscription-id>

terraform init
terraform plan
terraform apply
```

A first apply takes about 25-40 minutes. PostgreSQL with zone-redundant HA and Managed Redis are the slow parts.

To use the module from another configuration:

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

Every input has a default except `location`. See [terraform/variables.tf](terraform/variables.tf) and [terraform/examples/terraform.tfvars.example](terraform/examples/terraform.tfvars.example).

### What gets created

- **Resource group** `<name>-rg`. Set `create_resource_group = false` and `resource_group_name` to reuse an existing one.
- **VNet** with three subnets, plus a **NAT gateway** and its public IP.
- **AKS** `<name>`:
  - Workload Identity and the OIDC issuer are enabled.
  - Local accounts are disabled, so access goes through Entra ID. The identity running Terraform is granted *AKS RBAC Cluster Admin*, the equivalent of EKS's creator-admin.
  - The control plane runs on a user-assigned identity with *Network Contributor* on the resource group. That lets it attach the static public IPs.
- **PostgreSQL Flexible Server** `<name>-<suffix>-postgres`: private DNS zone, PITR backups (14 days by default) and a Monday 04:00 UTC maintenance window.
- **Azure Managed Redis** `<name>-<suffix>-redis`, with a private endpoint and the `privatelink.redis.azure.net` zone.
- **Storage account** `plane<suffix>` with the `uploads` container, a private endpoint and the `privatelink.blob.core.windows.net` zone. Shared-key auth is disabled.
- **Key Vault** `<name>-kv-<suffix>`. It holds generated credentials as JSON:

  | Secret | Keys |
  |---|---|
  | `plane-postgres` | `username`, `password`, `host`, `port`, `dbname` |
  | `plane-redis` | `host`, `port`, `password` |
  | `plane-rabbitmq` | `username`, `password` |
  | `plane-opensearch` | `username`, `password` |
  | `plane-minio` | `username`, `password` (interim in-cluster MinIO) |
  | `plane-app-keys` | `SECRET_KEY`, `AES_SECRET_KEY`, `LIVE_SERVER_SECRET_KEY`, `PI_INTERNAL_SECRET`, `SILO_HMAC_SECRET_KEY` |

  `SECRET_KEY` and `AES_SECRET_KEY` encrypt data at rest. Never regenerate them for an existing installation.
- **Managed identities** with federated credentials:
  - `<name>-plane-workload` trusts `system:serviceaccount:plane:plane-srv-account` and has *Storage Blob Data Contributor* on the storage account.
  - `<name>-external-secrets` trusts `system:serviceaccount:plane:plane-keyvault-reader` and has *Key Vault Secrets User* on the vault.
- **Public IPs**: `<name>-ingress-pip`, plus `<name>-email-pip` when `enable_email_public_ip = true`.

### Outputs

| Output | Used for |
|---|---|
| `configure_kubectl` | Cluster access |
| `postgres_fqdn`, `redis_hostname`, `redis_port` | Chart `env.pgdb_host`, `env.redis_host`, `env.redis_port` |
| `storage_account_name`, `storage_container_name` | Chart `env.azure_storage_*`, once the Azure Blob provider ships |
| `key_vault_uri`, `tenant_id`, `keyvault_reader_identity_client_id` | [examples/eso-keyvault.yaml](examples/eso-keyvault.yaml) |
| `plane_workload_identity_client_id` | Chart `serviceAccount.annotations` |
| `ingress_public_ip`, `ingress_public_ip_name`, `resource_group_name` | [examples/traefik-values.yaml](examples/traefik-values.yaml) and your DNS A record |
| `email_public_ip`, `email_public_ip_name` | MX record and the email Service annotation |
| `nat_public_ip` | Allow-listing Plane's egress on external systems |
| `helm_values` | A ready-to-merge chart values fragment |

## Step 2: Cluster add-ons

```bash
eval "$(terraform output -raw configure_kubectl)"

helm repo add jetstack https://charts.jetstack.io
helm repo add external-secrets https://charts.external-secrets.io
helm repo add traefik https://traefik.github.io/charts
helm repo add plane https://helm.plane.so
helm repo update

# cert-manager (Let's Encrypt certificates for the ingress)
helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --create-namespace \
  --set crds.enabled=true

# External Secrets Operator (Key Vault -> Kubernetes Secrets)
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace

# Traefik on the static ingress IP (fill the placeholders first)
helm upgrade --install traefik traefik/traefik -n traefik --create-namespace \
  -f ../../examples/traefik-values.yaml
```

Point your Plane hostname's DNS A record at `terraform output -raw ingress_public_ip`.

## Step 3: Deploy Plane

```bash
kubectl create namespace plane

# Mirror Key Vault secrets (fill the placeholders first)
kubectl apply -n plane -f ../../examples/eso-keyvault.yaml
kubectl get externalsecrets -n plane    # all should be SecretSynced

KV=$(terraform output -raw key_vault_name)
helm upgrade --install plane plane/plane-enterprise -n plane \
  -f ../../examples/values-azure.yaml \
  -f <(terraform output -raw helm_values) \
  --set services.minio.root_user=plane \
  --set services.minio.root_password="$(az keyvault secret show --vault-name "$KV" -n plane-minio --query value -o tsv | jq -r .password)" \
  --set services.rabbitmq.default_password="$(az keyvault secret show --vault-name "$KV" -n plane-rabbitmq --query value -o tsv | jq -r .password)" \
  --set services.opensearch.password="$(az keyvault secret show --vault-name "$KV" -n plane-opensearch --query value -o tsv | jq -r .password)"
```

The release name must match the ServiceAccount the workload identity trusts. Release `plane` creates `plane-srv-account`, which is the module default for `plane_service_account`.

### Inbound email (optional)

With `enable_email_public_ip = true` and `services.email_service.enabled: true`, pin the chart's email LoadBalancer Service to the static IP. The chart does not template Service annotations yet, so annotate the Service after install; Helm leaves annotations it did not set in place:

```bash
kubectl annotate service plane-email-service -n plane --overwrite \
  service.beta.kubernetes.io/azure-load-balancer-resource-group="$(terraform output -raw resource_group_name)" \
  service.beta.kubernetes.io/azure-pip-name="$(terraform output -raw email_public_ip_name)"
```

Then create DNS records:

| Type | Name | Value |
|---|---|---|
| MX | `yourdomain.com` | `10 mail.yourdomain.com.` |
| A | `mail.yourdomain.com` | `<email_public_ip>` |

Azure blocks **outbound** port 25 from most subscription types, but inbound SMTP is allowed.

## Operations

- **Key Vault firewall:** set `key_vault.allowed_ips` to the address you run Terraform from. The cluster's NAT egress IP is added automatically so External Secrets can read the vault. Alternatively, set `private_endpoint_enabled = true`, but Terraform then has to run from inside the VNet to manage secrets.
- **Upgrades:** AKS uses the `patch` auto-upgrade channel and weekly node-image updates. Pin `kubernetes_version` as `major.minor`.
- **Backups:** PostgreSQL keeps point-in-time restore for `backup_retention_days`. Set `geo_redundant_backup_enabled` at creation if you need cross-region restore; it cannot be changed later. Blob soft delete keeps deleted uploads for `soft_delete_retention_days`.
- **State:** Terraform state contains the generated passwords, as it does for the AWS module. Use a remote backend with encryption, such as an Azure Storage backend.

## Cleanup

```bash
helm uninstall plane -n plane         # releases the public IPs and disks AKS attached
terraform destroy
```

**Warning:** this deletes the PostgreSQL server (with its backups), Redis, the storage account and all uploads. With purge protection on, the Key Vault stays soft-deleted for `soft_delete_retention_days`. The random suffix means a re-deploy does not collide with it.
