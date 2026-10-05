# Plane on Azure

Deploy [Plane](https://plane.so) on Azure Kubernetes Service (AKS). This directory provides:

1. **Terraform** ([terraform/](terraform/)): provisions the Azure infrastructure. That means a VNet with a NAT gateway, AKS, PostgreSQL Flexible Server, Azure Managed Redis, Blob storage, Key Vault, workload identities and static public IPs.
2. **Helm**: deploys Plane on the cluster with the [plane-enterprise chart](https://github.com/makeplane/helm-charts/tree/master/charts/plane-enterprise). Credentials come from Key Vault through the External Secrets Operator.

For the architecture, every input, and how each Azure service maps to its AWS counterpart, see [terraform/README.md](terraform/README.md).

> **Object storage:** Plane does not have a native Azure Blob storage provider yet. Until it ships, Plane stores uploads in the chart's bundled **MinIO** on a Premium SSD volume, and this guide deploys it that way. Terraform already creates the Blob storage account, so switching later is a Helm values change.

## Prerequisites

- **Terraform** >= 1.5: [Download](https://developer.hashicorp.com/terraform/downloads)
- **Azure CLI**: [Install](https://learn.microsoft.com/cli/azure/install-azure-cli)
- **kubectl** and **kubelogin** (`az aks install-cli`). AKS logins go through Entra ID, so kubelogin is required.
- **Helm** 3: [Install](https://helm.sh/docs/intro/install/)
- **jq**

### Azure subscription

The identity running Terraform needs **Owner** on the subscription, or **Contributor + User Access Administrator**. The module creates role assignments (cluster admin, Blob and Key Vault access), and Contributor alone cannot do that.

```bash
az login
az account set --subscription "<subscription-id>"
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

Register the resource providers the module uses. This is a one-time step per subscription, is free, and Terraform does **not** do it for you:

```bash
for ns in Microsoft.ContainerService Microsoft.DBforPostgreSQL Microsoft.Cache \
          Microsoft.Storage Microsoft.KeyVault Microsoft.Network Microsoft.ManagedIdentity; do
  az provider register --namespace "$ns" --wait
done
```

Check your **vCPU quota** in the target region. The default sizing (two `Standard_D4ds_v5` system nodes and three workload nodes) needs **20 vCPUs** of the `DDSv5` family, plus headroom for autoscaling and upgrades. New subscriptions often allow only 10 regional vCPUs, with some families at 0:

```bash
az vm list-usage --location eastus2 -o table | grep -E "Total Regional vCPUs|DDSv5"
```

If the limit is too low, request an increase in the Azure portal (**Quotas → Compute**), or choose smaller sizes (see [Small / test deployments](#small--test-deployments)).

Pick a region with availability zones, Azure Managed Redis and zone-redundant PostgreSQL HA, for example `eastus2`, `westus3`, `northeurope` or `westeurope`.

---

## Step 1: Deploy Infrastructure (Terraform)

Create an empty directory for your deployment, for example `plane-azure/`, and add a `main.tf`:

### Minimal Configuration

```hcl
module "plane_infra" {
  source = "git::https://github.com/makeplane/commercial-deployments.git//azure/terraform?ref=main"
  # source = "../commercial-deployments/azure/terraform"  # for local development

  name     = "plane-aks"   # prefixes every resource; also the AKS cluster name
  location = "eastus2"     # required

  tags = {
    Environment = "plane"
  }
}
```

`location` is the only required input. With the defaults you get:
- a 3-zone AKS cluster with a 2-node system pool and a 3-to-6-node `plane` pool
- zone-redundant PostgreSQL 16 with the `plane` and `plane_pi` databases
- highly available Managed Redis
- ZRS Blob storage
- a Key Vault with generated credentials

Then run:

```bash
terraform init
terraform plan
terraform apply
```

A first apply takes about **25–40 minutes**. PostgreSQL HA and Managed Redis are the slow parts.

The subscription comes from `ARM_SUBSCRIPTION_ID`, or from your `az login` default. To set it explicitly, add `subscription_id = "<id>"` to the module block.

### Customized Configuration

Override any group of settings by passing the whole object. These are the defaults:

```hcl
module "plane_infra" {
  source = "git::https://github.com/makeplane/commercial-deployments.git//azure/terraform?ref=main"

  name               = "plane-aks"
  location           = "eastus2"
  vnet_cidr          = "10.0.0.0/16"
  zones              = ["1", "2", "3"]
  kubernetes_version = null # AKS default; pin as "major.minor", e.g. "1.34"

  aks = {
    sku_tier                        = "Standard" # uptime SLA; "Free" for test clusters
    system_node_vm_size             = "Standard_D4ds_v5"
    system_node_min_count           = 2
    system_node_max_count           = 3
    workload_node_pool_name         = "plane"
    workload_node_vm_size           = "Standard_D4ds_v5"
    workload_node_min_count         = 3
    workload_node_max_count         = 6
    node_os_disk_size_gb            = 128
    admin_group_object_ids          = []    # Entra ID groups granted cluster-admin
    api_server_authorized_ip_ranges = []    # e.g. ["203.0.113.10/32"]; empty = open
    local_account_disabled          = true
    pod_cidr                        = "192.168.0.0/16"
    service_cidr                    = "172.16.0.0/16"
    dns_service_ip                  = "172.16.0.10"
  }

  postgres = {
    engine_version               = "16"
    sku_name                     = "GP_Standard_D4ds_v5"
    storage_mb                   = 131072 # auto-grow is on
    high_availability_mode       = "ZoneRedundant" # or "SameZone" / "Disabled"
    backup_retention_days        = 14
    geo_redundant_backup_enabled = false  # can only be set at creation
    administrator_login          = "planeadmin"
    database_names               = ["plane", "plane_pi"]
  }

  redis = {
    sku_name                  = "Balanced_B1"
    high_availability_enabled = true
    clustering_policy         = "NoCluster" # or "EnterpriseCluster"
  }

  object_store = {
    account_name_prefix           = "plane"
    replication_type              = "ZRS"
    container_name                = "uploads"
    versioning_enabled            = false
    soft_delete_retention_days    = 7
    public_network_access_enabled = false
  }

  key_vault = {
    allowed_ips                   = [] # set to your egress IP(s) to turn the vault firewall on
    public_network_access_enabled = true
    private_endpoint_enabled      = false
    purge_protection_enabled      = true
    soft_delete_retention_days    = 30
  }

  tags = {
    Environment = "plane"
  }
}
```

See [terraform/README.md](terraform/README.md#inputs) for every input, including `create_resource_group`/`resource_group_name`, which deploy into an existing resource group.

### Small / test deployments

Sizing that fits a subscription with a **10 vCPU** regional quota: one 2-vCPU system node plus two 4-vCPU workload nodes, burstable PostgreSQL, and no HA. It works for evaluation, but autoscaling and upgrade surge have no headroom.

```hcl
module "plane_infra" {
  source = "git::https://github.com/makeplane/commercial-deployments.git//azure/terraform?ref=main"

  name     = "plane-test"
  location = "eastus2"

  aks = {
    sku_tier                        = "Free"
    system_node_vm_size             = "Standard_D2ds_v4"
    system_node_min_count           = 1
    system_node_max_count           = 1
    workload_node_pool_name         = "plane"
    workload_node_vm_size           = "Standard_D4ds_v4"
    workload_node_min_count         = 2
    workload_node_max_count         = 2
    node_os_disk_size_gb            = 64
    admin_group_object_ids          = []
    api_server_authorized_ip_ranges = []
    local_account_disabled          = true
    pod_cidr                        = "192.168.0.0/16"
    service_cidr                    = "172.16.0.0/16"
    dns_service_ip                  = "172.16.0.10"
  }

  postgres = {
    engine_version               = "16"
    sku_name                     = "B_Standard_B2ms" # burstable tiers do not support HA
    storage_mb                   = 32768
    high_availability_mode       = "Disabled"
    backup_retention_days        = 7
    geo_redundant_backup_enabled = false
    administrator_login          = "planeadmin"
    database_names               = ["plane", "plane_pi"]
  }

  redis = {
    sku_name                  = "Balanced_B0"
    high_availability_enabled = false
    clustering_policy         = "NoCluster"
  }

  key_vault = {
    allowed_ips                   = []
    public_network_access_enabled = true
    private_endpoint_enabled      = false
    purge_protection_enabled      = false # lets `terraform destroy` remove the vault completely
    soft_delete_retention_days    = 7
  }
}
```

### Inbound Email (optional)

Plane includes an email service for receiving inbound email. To give it a static public IP for your MX record, set:

```hcl
module "plane_infra" {
  # ...
  enable_email_public_ip = true
}
```

Unlike AWS, this needs only one stage. The email Service is a Kubernetes `LoadBalancer` bound to this IP, so there are no NodePorts and no separate load balancer. See [Step 2](#inbound-email) for wiring it up.

### Outputs

Add these output blocks to your configuration, for example in `outputs.tf`. Step 2 reads them with `terraform output`, so keep the names:

```hcl
output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = module.plane_infra.configure_kubectl
}

output "resource_group_name" {
  description = "Resource group holding every resource"
  value       = module.plane_infra.resource_group_name
}

output "tenant_id" {
  description = "Entra ID tenant"
  value       = module.plane_infra.tenant_id
}

output "postgres_fqdn" {
  description = "PostgreSQL private FQDN"
  value       = module.plane_infra.postgres_fqdn
}

output "redis_hostname" {
  description = "Redis hostname"
  value       = module.plane_infra.redis_hostname
}

output "storage_account_name" {
  description = "Storage account for uploads (native Blob provider)"
  value       = module.plane_infra.storage_account_name
}

output "key_vault_name" {
  description = "Key Vault holding the generated credentials"
  value       = module.plane_infra.key_vault_name
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = module.plane_infra.key_vault_uri
}

output "plane_workload_identity_client_id" {
  description = "Client ID for the Plane ServiceAccount"
  value       = module.plane_infra.plane_workload_identity_client_id
}

output "keyvault_reader_identity_client_id" {
  description = "Client ID for the Key Vault SecretStore ServiceAccount"
  value       = module.plane_infra.keyvault_reader_identity_client_id
}

output "ingress_public_ip" {
  description = "Ingress public IP; point your Plane DNS record here"
  value       = module.plane_infra.ingress_public_ip
}

output "ingress_public_ip_name" {
  description = "Name of the ingress public IP"
  value       = module.plane_infra.ingress_public_ip_name
}

output "email_public_ip" {
  description = "Email public IP (null unless enable_email_public_ip)"
  value       = module.plane_infra.email_public_ip
}

output "email_public_ip_name" {
  description = "Name of the email public IP"
  value       = module.plane_infra.email_public_ip_name
}

output "nat_public_ip" {
  description = "Egress IP of the cluster; allow-list it on external systems"
  value       = module.plane_infra.nat_public_ip
}

output "helm_values" {
  description = "plane-enterprise values derived from this infrastructure"
  value       = module.plane_infra.helm_values
}
```

| Output | Description |
|---|---|
| `configure_kubectl` | Command to fetch cluster credentials (az + kubelogin) |
| `resource_group_name` | Resource group holding every resource |
| `tenant_id` | Entra ID tenant |
| `postgres_fqdn` | PostgreSQL private FQDN (resolvable only inside the VNet) |
| `redis_hostname` | Managed Redis hostname (TLS, port 10000) |
| `storage_account_name` | Blob storage account (for the native Blob provider, once it ships) |
| `key_vault_name` / `key_vault_uri` | Key Vault holding the generated credentials |
| `plane_workload_identity_client_id` | Workload identity for the Plane pods |
| `keyvault_reader_identity_client_id` | Workload identity for the Key Vault SecretStore |
| `ingress_public_ip` / `ingress_public_ip_name` | Static IP for the ingress controller |
| `email_public_ip` / `email_public_ip_name` | Static IP for inbound email (when enabled) |
| `nat_public_ip` | Cluster egress IP |
| `helm_values` | plane-enterprise values fragment (identity, PostgreSQL, Redis, storage class) |

The module has more outputs, such as the VNet and subnet IDs and the AKS OIDC issuer. See [terraform/outputs.tf](terraform/outputs.tf).

### Configure kubectl

```bash
eval "$(terraform output -raw configure_kubectl)"
kubectl get nodes
```

This runs `az aks get-credentials` followed by `kubelogin convert-kubeconfig -l azurecli`. Local cluster accounts are disabled. The identity that ran Terraform is granted *Azure Kubernetes Service RBAC Cluster Admin*; grant other people that role, or add their group to `aks.admin_group_object_ids`.

---

## Step 2: Deploy Plane (Helm)

Run these commands from your Terraform directory, so that `terraform output` works.

### 2a. Cluster add-ons

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo add external-secrets https://charts.external-secrets.io
helm repo add traefik https://traefik.github.io/charts
helm repo add plane https://helm.plane.so/
helm repo update

# cert-manager: Let's Encrypt certificates for the Plane hostname
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace --set crds.enabled=true

# External Secrets Operator: mirrors Key Vault secrets into Kubernetes Secrets
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace

# Traefik, bound to the static ingress IP
helm upgrade --install traefik traefik/traefik -n traefik --create-namespace -f - <<EOF
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-resource-group: $(terraform output -raw resource_group_name)
    service.beta.kubernetes.io/azure-pip-name: $(terraform output -raw ingress_public_ip_name)
  spec:
    externalTrafficPolicy: Local
deployment:
  replicas: 2
EOF
```

Create a DNS **A record** for your Plane hostname (for example `plane.example.com`) pointing at:

```bash
terraform output -raw ingress_public_ip
```

### 2b. Secrets from Key Vault

```bash
kubectl create namespace plane

kubectl apply -n plane -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: plane-keyvault-reader
  annotations:
    azure.workload.identity/client-id: $(terraform output -raw keyvault_reader_identity_client_id)
    azure.workload.identity/tenant-id: $(terraform output -raw tenant_id)
---
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: plane-azure-keyvault
spec:
  provider:
    azurekv:
      authType: WorkloadIdentity
      vaultUrl: $(terraform output -raw key_vault_uri)
      serviceAccountRef:
        name: plane-keyvault-reader
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: plane-postgres
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: SecretStore, name: plane-azure-keyvault }
  target: { name: plane-postgres }
  dataFrom: [{ extract: { key: plane-postgres } }]
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: plane-redis
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: SecretStore, name: plane-azure-keyvault }
  target: { name: plane-redis }
  dataFrom: [{ extract: { key: plane-redis } }]
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: plane-app-keys
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: SecretStore, name: plane-azure-keyvault }
  target: { name: plane-app-keys }
  dataFrom: [{ extract: { key: plane-app-keys } }]
EOF

kubectl get externalsecrets -n plane   # wait until all three show SecretSynced
```

The ServiceAccount name `plane-keyvault-reader` and the namespace `plane` must match the module's `eso_service_account` and `plane_namespace` inputs. Those are the defaults.

### 2c. Install Plane

```bash
curl -fsSLO https://raw.githubusercontent.com/makeplane/commercial-deployments/main/azure/examples/values-azure.yaml
# Edit values-azure.yaml: set license.licenseDomain to your Plane hostname and ssl.email.

KV=$(terraform output -raw key_vault_name)
kv_password() { az keyvault secret show --vault-name "$KV" -n "$1" --query value -o tsv | jq -r .password; }

helm upgrade --install plane plane/plane-enterprise -n plane \
  -f values-azure.yaml \
  -f <(terraform output -raw helm_values) \
  --set services.minio.root_user=plane \
  --set services.minio.root_password="$(kv_password plane-minio)" \
  --set services.rabbitmq.default_password="$(kv_password plane-rabbitmq)" \
  --set services.opensearch.password="$(kv_password plane-opensearch)"
```

[values-azure.yaml](examples/values-azure.yaml) configures the following, and `helm_values` fills in the identity client ID and the PostgreSQL and Redis hosts:

| Component | Configuration |
|---|---|
| PostgreSQL | Managed, with credentials from the `plane-postgres` Secret |
| Redis | Managed: TLS on port 10000, with the access key from the `plane-redis` Secret |
| App keys | Signing and encryption keys from the `plane-app-keys` Secret |
| RabbitMQ, OpenSearch | In-cluster (Azure has no managed equivalents) |
| MinIO | In-cluster on `managed-csi-premium` |
| Ingress | Traefik with Let's Encrypt certificates |

The release name must be `plane`. The chart then creates the ServiceAccount `plane-srv-account`, which is the account the Plane workload identity trusts (the module input `plane_service_account`).

Watch the rollout:

```bash
kubectl get pods -n plane -w
```

Once the migrator job completes and the pods are ready, open `https://<your Plane hostname>`.

### Inbound Email

With `enable_email_public_ip = true`, enable the email service (`--set services.email_service.enabled=true`). Then pin its LoadBalancer Service to the static IP. The chart does not template annotations for this Service yet, so add them after install; Helm leaves annotations it did not set in place.

```bash
kubectl annotate service plane-email-service -n plane --overwrite \
  service.beta.kubernetes.io/azure-load-balancer-resource-group="$(terraform output -raw resource_group_name)" \
  service.beta.kubernetes.io/azure-pip-name="$(terraform output -raw email_public_ip_name)"
```

DNS records for your mail domain:

| Type | Name | TTL | Value |
|---|---|---|---|
| A | `mail.yourdomain.com` | 300 | `<email_public_ip>` |
| MX | `yourdomain.com` | 300 | `10 mail.yourdomain.com.` |

The Service listens on port **25** (SMTP), **465** (SMTPS) and **587** (Submission). Azure blocks *outbound* port 25 from most subscriptions; inbound is allowed.

---

## Cleanup

```bash
# Release the static IPs from the AKS load balancer first, or destroying them fails with "in use"
helm uninstall traefik -n traefik
kubectl delete service plane-email-service -n plane --ignore-not-found

terraform destroy   # deletes the cluster, including every node and persistent volume
```

**Warning:** this deletes all data in PostgreSQL (including its backups), Redis, the in-cluster MinIO, RabbitMQ and OpenSearch volumes, and the storage account. Take backups first if you need them. With `purge_protection_enabled = true`, the Key Vault stays soft-deleted for `soft_delete_retention_days`. A redeploy does not collide with it, because the vault name has a random suffix.
