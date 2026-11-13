# Deploying Plane on Azure

> **Not yet proven on Azure.** This module hasn't run on a real Azure subscription yet. This guide comes from the
> module's code and Microsoft's documentation, not from an observed install, so timings are rough expectations and we
> don't state costs. The module also needs Plane's Azure Blob support and the matching chart release, which are still
> being built; until they ship it can't install a working Plane (see "Requires" in the [README](../README.md)).

This guide takes you from an Azure subscription to a running Plane Commercial installation, using the
`terraform-azurerm-plane` module. One `terraform apply` creates the network, an AKS cluster, managed data services, Blob
Storage and Plane itself. You then create a few DNS records and, depending on the path you choose, finish the ingress
setup.

## Contents

1. [What gets deployed](#1-what-gets-deployed)
2. [Before you start](#2-before-you-start)
3. [Choose how traffic reaches Plane](#3-choose-how-traffic-reaches-plane)
4. [Set up Terraform state](#4-set-up-terraform-state)
5. [Configure](#5-configure)
6. [Deploy](#6-deploy)
7. [Create the DNS records](#7-create-the-dns-records)
8. [Finish the ingress setup](#8-finish-the-ingress-setup)
9. [Sign in and activate your licence](#9-sign-in-and-activate-your-licence)
10. [Day-2 operations](#10-day-2-operations)
11. [Removing the installation](#11-removing-the-installation)
12. [Troubleshooting](#12-troubleshooting)

## 1. What gets deployed

```
 Users -> static IP or your ingress          Mail servers -> static IP (25, 465, 587)
+- VNet -------------------------------------------------------------------+
|  AKS: Traefik (path A) -> Plane; Email; RabbitMQ and OpenSearch on disks |
|  Private: PostgreSQL Flexible Server, Managed Redis, Blob Storage        |
+----------------------- NAT gateway (static IP) -> Key Vault, internet ---+
```

| Part | What | Default size |
|---|---|---|
| Resource group | `<name>-rg`, or an existing empty one. AKS adds its own node resource group, `<resource group>-<name>-nodes` | |
| Network | A new VNet with a subnet each for AKS nodes, PostgreSQL and private endpoints, and a NAT gateway on a static IP. Nodes reach the internet only through the NAT gateway | `10.60.0.0/16` |
| Kubernetes | AKS with Entra ID and Azure RBAC (local accounts off), Workload Identity, Azure CNI Overlay with Cilium, one node pool scaled by the cluster autoscaler, Azure Linux | Kubernetes 1.36, Standard tier, 2 × `Standard_D4ds_v5` over zones 1–3 (range 2–4) |
| Database | Azure Database for PostgreSQL Flexible Server 15, zone-redundant high availability, VNet-integrated, encrypted connections only. Databases `plane` and `plane_pi` | `GP_Standard_D2ds_v5`, 128 GB, grows automatically, 14 days of backups, delete lock |
| Cache | Azure Managed Redis behind a private endpoint, high availability, TLS on port 10000, an RDB snapshot every 12 hours | `Balanced_B3` (3 GB) |
| Message queue | RabbitMQ, **run in the cluster** | One node, 10 GiB Premium ZRS disk |
| Search | OpenSearch, **run in the cluster** | One node, 50 GiB Premium ZRS disk |
| File storage | A Blob container in a StorageV2 account behind a private endpoint. Versioning, 7-day soft delete, previous versions deleted after 30 days | ZRS, delete lock |
| Secrets | Key Vault in RBAC mode with purge protection, holding the generated passwords and keys | |
| Email | Plane's email service on its own load balancer and static public IP, receiving mail for `intake.<your domain>` | |
| Plane | The Plane Commercial Helm chart, plus External Secrets and Reloader. Path A also installs Traefik and, with Let's Encrypt, cert-manager | api, worker, web and live run 2 replicas |

**RabbitMQ and OpenSearch run inside the cluster.** Azure has no managed AMQP 0-9-1 service or managed OpenSearch, so
the module runs each as a single instance. Their zone-redundant disks let a pod restart in another zone, but neither is
highly available. You operate them: back them up with disk snapshots (section 10). Search is optional: set
`opensearch = { enabled = false }` to turn it off.

**Files go through Plane.** On Azure, every upload and download passes through Plane's api pods, which read and write
Blob over the private endpoint. Browsers never talk to the storage account, so there is no SAS and no CORS. Size the api
pods for your file traffic, and keep any ingress body limit at least as large as your upload limit. On path A that limit
is 20 MiB by default: raise it with `ingress.traefik.maxRequestBodyBytes` in `plane_values`. The module's
`use_storage_proxy` input can only be `true` on Azure; the module refuses `false`, as do the chart and the api.
[Plane AI](#plane-ai-optional) is optional and off by default.

**Security defaults:**
- Only the load balancers, the AKS API endpoint and the Key Vault endpoint are public. Limit the AKS API, open to all
  addresses by default, with `api_server_authorized_ip_ranges`. Key Vault is gated by Entra ID RBAC;
  `key_vault.allowed_ips` turns on its firewall.
- PostgreSQL, Redis and Blob Storage have no public access. PostgreSQL accepts only encrypted connections; Redis uses
  TLS and an access key, because Plane's clients send only a password. The storage account has shared keys turned off.
- Data is encrypted at rest with platform-managed keys. Customer-managed keys are not supported in this release.
- Plane reaches Blob, and External Secrets reaches Key Vault, through Azure Workload Identity: no client secrets or
  storage keys. Plane holds *Storage Blob Data Contributor* on the uploads container only. External Secrets holds *Key
  Vault Secrets User* on the module's vault and on the individual secrets you name.
- Passwords and keys are generated for you, and kept in Key Vault and the Terraform state.

Every size above can be changed in `terraform.tfvars`; the RabbitMQ and OpenSearch disk sizes only before the first
install (section 10 explains how to grow those disks later). For costs, enter these sizes in the Azure pricing
calculator for your region.

## 2. Before you start

### Tools

| Tool | Version | Used for |
|---|---|---|
| Terraform | 1.10 or later | The deployment |
| Azure CLI | any recent | Authentication, and the state storage account |
| kubelogin | any recent | Helm's and kubectl's authentication to AKS during and after the apply (`az aks install-cli`) |
| kubectl | any recent | Checking the installation (`az aks install-cli`) |
| Helm | 3 or later | Only if you bring your own ingress (path B) |
| AzCopy | any recent | Only to copy your uploads out before removing the installation |

### Azure subscription

- **Permissions.** **Owner** on the subscription (or the resource group), or **Contributor** plus **User Access
  Administrator**. The module creates role assignments (Azure Kubernetes Service RBAC Cluster Admin, Network Contributor,
  Key Vault Secrets Officer and User, Storage Blob Data Contributor) and delete locks. No Entra ID directory roles are
  needed: the module uses managed identities only.
- **Resource providers.** Register `Microsoft.ContainerService`, `Microsoft.Network`, `Microsoft.Compute`,
  `Microsoft.DBforPostgreSQL`, `Microsoft.Cache`, `Microsoft.KeyVault`, `Microsoft.ManagedIdentity` and
  `Microsoft.Storage` with `az provider register --namespace <name>`.
- **Region.** It must offer 3 availability zones, Azure Managed Redis, zone-redundant PostgreSQL high availability and
  Premium ZRS disks, for example `eastus2`, `westus3`, `northeurope` or `westeurope`.
- **Quotas** in the region: at least 24 DDSv5 vCPUs (4 per default node, up to 4 nodes, plus surge nodes during upgrades),
  4 PostgreSQL vCores (server and standby) and 3 Standard public IPs (web, email and NAT).
- **Azure Policy.** Assignments that deny public IPs, LoadBalancer Services, Redis access keys or Key Vault public access
  break the defaults. Check yours first.
- **Network access** from where you run Terraform to the AKS API and to Key Vault.

### Domain, DNS and licence

- **A domain for Plane**, for example `plane.example.com`. **It can never change after installation:** your Plane licence
  is bound to it.
- **Access to the DNS zone.** You create the DNS records after the apply; the module never changes your DNS.
- **An email domain** for inbound email to work items. The default is `intake.<your domain>`.
- **A Plane Commercial licence key**, which you activate after installation.

## 3. Choose how traffic reaches Plane

Pick one path before you configure.

| Path | Choose it when | The module installs | You do after the apply |
|---|---|---|---|
| **A.1: Automated, Let's Encrypt** | Plane is reachable from the internet, and a free Let's Encrypt certificate is fine | Traefik behind an Azure load balancer on a static public IP, Plane's routes, and a Let's Encrypt certificate | Create the DNS records |
| **A.2: Automated, your certificate** | You have your own certificate, or Plane is internal only | Traefik behind an Azure load balancer on a static IP, Plane's routes, and your certificate | Import the certificate into Key Vault first; create the DNS records |
| **B: Bring your own ingress** (default) | You run your own ingress controller (NGINX, your own Traefik, Application Gateway for Containers, …) or certificate tooling | No ingress controller and no routes | Install your controller, apply Plane's routes, add the certificate, create the DNS records |

**About A.1:** Let's Encrypt checks domain ownership over HTTP, so Plane must be reachable from the whole internet on
port 80. The certificate is issued once your DNS record points at the load balancer, and it renews automatically. If you
need to restrict who can reach Plane, choose A.2 or B.

**Email certificate (any path):** the email service uses a certificate for encrypted mail. If you don't provide one, it
generates a self-signed certificate. That's fine for receiving mail from other mail servers. To use a trusted one, import
it into Key Vault (next section) and set `email.certificate_secret_id`.

### Importing a certificate into Key Vault (A.2 and email)

Use a Key Vault of yours, because the module's own vault doesn't exist before the first apply. It must be in the **same
subscription** as Plane and use the **RBAC permission model**. To import, you need a data-plane role on it, such as *Key
Vault Certificates Officer*: Owner alone doesn't grant one. Import PEM or PFX, with the full chain and the private key:

```bash
az keyvault certificate import --vault-name <vault> --name plane-web --file fullchain-and-key.pem
```

Refer to it in `terraform.tfvars` by its **versionless resource ID**, which the module checks at plan
(`az keyvault certificate show` prints a versioned URL, which is not this form):

```
/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault>/certificates/plane-web
```

One certificate can serve both web and email if it lists both names. The module grants External Secrets *Key Vault
Secrets User* on that certificate only. If the vault has a firewall, allow the cluster's egress IP (see
[Plane AI](#plane-ai-optional) for how to get it before the first apply).

## 4. Set up Terraform state

Terraform state contains generated secrets (the database and RabbitMQ passwords, the Redis key and Plane's app keys), so
keep it in a private storage account that only the people and pipelines who deploy Plane can access. Create the account
with versioning and soft delete on and shared keys off, and give yourself access through Entra ID:

```bash
az group create --name <state-rg> --location <region>
az storage account create --name <statestorage> --resource-group <state-rg> --location <region> \
  --sku Standard_ZRS --kind StorageV2 --min-tls-version TLS1_2 \
  --allow-blob-public-access false --allow-shared-key-access false
az storage account blob-service-properties update --account-name <statestorage> --resource-group <state-rg> \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 30
az role assignment create --role "Storage Blob Data Contributor" \
  --assignee "$(az ad signed-in-user show --query id -o tsv)" \
  --scope "$(az storage account show --name <statestorage> --resource-group <state-rg> --query id -o tsv)"
az storage container create --name tfstate --account-name <statestorage> --auth-mode login
```

The new role can take a few minutes to apply: if the last command is refused, wait and run it again. Everyone who runs
Terraform needs *Storage Blob Data Contributor* on this account. Keep this account outside the resource group Plane
deploys into, so it survives removing the installation.

## 5. Configure

Sign in with the Azure CLI, which Terraform and kubelogin both use (for a pipeline, change kubelogin's `--login` argument
in the `helm` provider block in `main.tf`). Get the module at the release you were given, and create your backend and
settings files. Set your state storage account in `backend.hcl`.

```bash
az login
az account set --subscription <subscription-id>
git clone https://github.com/makeplane/commercial-deployments.git
cd commercial-deployments
git checkout <release-tag>
cd azure/terraform-azure-plane/examples/complete
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` is the only file you edit. `terraform.tfvars.example` lists every setting with its default. Set the
required values and the block for your path:

```hcl
subscription_id = "00000000-0000-0000-0000-000000000000"
location        = "eastus2"
name            = "plane"             # prefix for all resources, 3–20 characters; never change it
domain          = "plane.example.com" # never change it

# Who can reach the AKS API (Terraform needs it during the apply). Use your network's ranges.
api_server_authorized_ip_ranges = ["203.0.113.0/24"]

# Path A.1: Let's Encrypt
ingress    = { mode = "automated" }
acme_email = "ops@example.com" # Let's Encrypt account email, for expiry notices

# Path A.2: your certificate (instead of the A.1 lines)
# ingress = { mode = "automated", tls_certificate_secret_id = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault>/certificates/plane-web" }

# Path B: bring your own ingress. Set nothing here.

# Optional: your email certificate (any path)
# email = { certificate_secret_id = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault>/certificates/plane-mail" }
```

**Common optional settings.** For objects, set only the fields you change.

| Setting | Example | Effect |
|---|---|---|
| Restrict who reaches Plane (A.2) | `ingress = { mode = "automated", tls_certificate_secret_id = "…", allowed_cidrs = ["10.0.0.0/8"] }` | The load balancer accepts only these ranges |
| Internal load balancer (A.2) | `ingress = { …, scheme = "internal" }` | Plane gets a fixed private IP in the AKS subnet, reachable only from the VNet or connected networks. Choose it before the first install; to change it later, see section 10 |
| More nodes | `node_pool = { max_count = 6 }` | The autoscaler can grow to 6 nodes. Check your vCPU quota |
| Larger database | `postgres = { sku_name = "GP_Standard_D4ds_v5" }` | 4 vCores |
| Backups in the paired region | `postgres = { geo_redundant_backup_enabled = true }` | Azure sets this only when it creates the server, so decide before the first install |
| Larger cache | `redis = { sku_name = "Balanced_B5" }` | 6 GB |
| No cache persistence | `redis = { persistence = false }` | No RDB snapshots. Required if you set `high_availability_enabled = false`: Azure has no persistence without high availability |
| No search | `opensearch = { enabled = false }` | No OpenSearch; Plane runs with search indexing off |
| Different network range | `vnet_cidr = "10.80.0.0/16"` | Avoids overlap with networks you connect. It must not overlap the fixed pod (`192.168.0.0/16`) and service (`172.16.0.0/16`) ranges either |
| Existing resource group | `resource_group = { create = false, name = "my-rg" }` | Deploys into your resource group, which must be empty |
| Key Vault firewall | `key_vault = { allowed_ips = ["203.0.113.10"] }` | Include the address Terraform runs from. The cluster's egress IP is added for you |

**For a test install you will destroy**, turn off the protections before the first apply: `terraform.tfvars.example`
ends with the settings. Purge protection can't be turned off once a vault has it.

### Plane AI (optional)

Plane AI runs on the same Blob container and in-cluster OpenSearch as Plane, with the `plane_pi` database. It needs Plane
at the first release whose Plane AI supports Azure Blob (named in the module's release notes; the module refuses older
ones), search on (`opensearch.enabled`, the default; OpenSearch then gets a 1.5 GB heap and a 3 GiB limit), and two API
keys: one for chat and a Cohere key for embeddings. The module refuses Plane AI without both.

**Choose the chat provider** (`pi.api_keys.chat_provider`). A vendor key gives Plane AI that vendor's models, and it
picks the default: `openai` (the default), `anthropic`, `xai`, `baseten` or `meta`. Or `custom`: your own model on any
OpenAI-compatible API (Plane AI's custom LLM), and only that model, such as an Azure OpenAI deployment. `custom` requires
an OpenAI-compatible API: the OpenAI Chat Completions API at `chat_base_url` (for example `https://host/v1`, serving
`/chat/completions`) with a bearer key. Azure OpenAI works through its `/openai/v1` endpoint; other APIs, such as
Anthropic's native API, don't: use a vendor value or a gateway such as LiteLLM. The module README's Plane AI section
compares them.

**1. Store the provider keys** in **one Key Vault of yours**, as plain-text secrets holding only the key, or as one JSON
secret holding both (each field named in `chat_key_json_field` and `embedding_key_json_field`): in this
subscription, using the RBAC permission model. The module's own vault doesn't exist yet. Writing them needs a data-plane
role such as *Key Vault Secrets Officer*, and Terraform needs permission to create role assignments on that vault.

```bash
az keyvault secret set --vault-name <vault> --name plane-openai-key --value "$OPENAI_API_KEY"
az keyvault secret set --vault-name <vault> --name plane-cohere-key --value "$COHERE_API_KEY"
```

The keys never appear in `terraform.tfvars`, the Terraform state or Helm values. External Secrets gets read access to
those secrets only, and copies them into the cluster.

If the vault has a firewall, allow the cluster's egress IP. It doesn't exist before the first apply, so run
`terraform init -backend-config=backend.hcl` and `terraform apply -target=module.plane.module.network`, get the IP with
`az network public-ip show --resource-group <name>-rg --name <name>-nat-pip --query ipAddress -o tsv`, allow it, then
continue.

**2. Turn Plane AI on** in `terraform.tfvars`, with each secret's versionless resource ID:

```hcl
enable_components = { pi = true }
pi = {
  api_keys = {
    chat_key_secret_id      = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault>/secrets/plane-openai-key"
    embedding_key_secret_id = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault>/secrets/plane-cohere-key"
  }
}
# plane_version = "<a release with Plane AI on Azure Blob>" # if the module's default is older
```

**Other providers.** For another vendor, store its key instead and set `chat_provider` (`"anthropic"`, `"xai"`,
`"baseten"` or `"meta"`). For a custom model, for example on Azure OpenAI:

```hcl
pi = {
  api_keys = {
    chat_provider           = "custom"
    chat_base_url           = "https://<resource>.openai.azure.com/openai/v1" # OpenAI-compatible API (Chat Completions)
    chat_model              = "<deployment name>"
    chat_key_secret_id      = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault>/secrets/plane-azure-openai-key"
    embedding_key_secret_id = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault>/secrets/plane-cohere-key"
  }
}
```

`chat_model_name` (shown in Plane AI) and `chat_max_tokens` (the model's context window, default 128000) are optional,
and only for `custom`. For another Cohere embedding model, set `embedding_model` (the module README lists them).

**Choose the embedding model before the first install**, even if you turn Plane AI on later. Plane's search indexes
take its vector dimension at the first install, whether Plane AI is on or not; without a `pi` setting that is Cohere
embed-v4.0 (1536). For another model, set `pi = { api_keys = { embedding_model = "…" } }` now. Changing it afterwards
needs Plane's search indexes and Plane AI's indexes recreated.

**Files and outbound access.** Clients reach Plane AI's files through its own signed routes under `/pi/` on your domain,
so every Plane AI file passes through its pods. The Plane AI pods call the chat model, and the OpenSearch pod calls the
embedding API, through the NAT gateway. If you restrict outbound traffic, allow HTTPS to the providers you use, for
example `api.cohere.ai` and your chat provider's API (`api.openai.com`, `api.anthropic.com`, or your custom endpoint).

## 6. Deploy

Before you apply, check that the plan only adds resources (`Plan: N to add, 0 to change, 0 to destroy`):

```bash
terraform init -backend-config=backend.hcl
terraform plan -out plane.tfplan
terraform apply plane.tfplan
```

We haven't measured the apply on Azure. As a rough expectation based on our other clouds, allow 40–70 minutes. The last
step (`helm_release.plane`) runs for a while without output, because database migrations on a new installation are
expected to take about 20 minutes. Terraform waits up to `helm_timeout` (one hour by default).

When it finishes, connect kubectl to the cluster. This signs in through Entra ID with kubelogin, because AKS local
accounts are off. Use `eval`, because the output is two commands:

```bash
eval "$(terraform output -raw configure_kubectl)"
kubectl -n plane get pods             # all Running or Completed
kubectl -n plane get externalsecrets  # all SecretSynced
```

## 7. Create the DNS records

Run `terraform output dns_records` and create these records:

| Record | Name | Type | Value |
|---|---|---|---|
| Web (paths A.1 and A.2) | your `domain` | A | the `web` value: the load balancer's static IP |
| Web (path B) | your `domain` | A | your own ingress controller's load balancer IP |
| Email host | your email domain (`intake.<domain>`) | A | the `email_host` value: the email load balancer's static IP |
| Email | your email domain (`intake.<domain>`) | MX | the `email_mx` value: `10 <email domain>` |

- The `type` of the A records reads `A (DNS-only, no proxy)`. Create plain A records. If your DNS provider can proxy
  traffic, as Cloudflare can, turn that off.
- The IPs are static, so A records are safe. An MX record can't point at an IP, so the email domain gets both an A record
  and an MX record naming itself.
- With `ingress.scheme = "internal"`, the web IP is private: create the record in a DNS zone your users resolve, for
  example a private zone.

## 8. Finish the ingress setup

### Path A.1

The certificate is issued after the web DNS record resolves. Until then, browsers show a certificate warning. Check
progress:

```bash
kubectl -n plane get certificate plane-tls   # READY becomes True
kubectl -n plane get challenges              # empty once issued
```

### Path A.2

Nothing more to do. `kubectl -n plane get externalsecret plane-web-tls` shows `SecretSynced` once the certificate is loaded
from Key Vault.

### Path B

1. **Install your ingress controller** if it isn't already in the cluster. On AKS, a controller whose Service has
   `type: LoadBalancer` gets an Azure load balancer automatically. As the module does for its own Traefik, set
   `externalTrafficPolicy: Local` to keep the client's IP, and the annotation
   `service.beta.kubernetes.io/azure-load-balancer-tcp-idle-timeout: "30"` so the default 4-minute idle timeout doesn't
   cut live collaboration's WebSockets. For a fixed address, create a Standard static public IP in the deployment's
   resource group and name it with `service.beta.kubernetes.io/azure-pip-name` and
   `service.beta.kubernetes.io/azure-load-balancer-resource-group`.
2. **Add your certificate** as a Kubernetes TLS Secret named `plane-tls` in namespace `plane`:
   ```bash
   kubectl -n plane create secret tls plane-tls --cert=fullchain.pem --key=privkey.pem
   ```
   Or let your own cert-manager create that Secret.
3. **Generate Plane's routes** for your controller from the exact values this installation uses:
   ```bash
   helm repo add plane https://helm.plane.so/
   terraform output -raw plane_helm_values > plane-values.yaml
   ```
   Then run the command for your controller. Use the chart version this installation uses (`chart_version` in
   `terraform.tfvars.example`, or your override). If you set `plane_values`, save it to a file and add it as a second
   `-f`.

   **Traefik:**
   ```bash
   helm template plane plane/plane-enterprise --version <chart_version> -n plane -f plane-values.yaml \
     --set ingress.enabled=true,ingress.controller=traefik \
     --show-only templates/ingress-traefik.yaml --show-only templates/traefik-middleware.yaml > plane-routes.yaml
   ```
   The routes use Traefik's `websecure` entry point.

   **NGINX:**
   ```bash
   helm template plane plane/plane-enterprise --version <chart_version> -n plane -f plane-values.yaml \
     --set ingress.enabled=true,ingress.controller=nginx,ingress.ingressClass=<your-ingress-class> \
     --set-string 'ingress.ingress_annotations.nginx\.ingress\.kubernetes\.io/proxy-body-size=20m' \
     --show-only templates/ingress-nginx.yaml > plane-routes.yaml
   ```
   Every upload passes through your controller on Azure: raise `20m` if your upload limit in Plane is higher.

   **Application Gateway for Containers and other controllers:** use the generated NGINX Ingress as the route table: each
   path, the service and port it goes to. Plane needs WebSocket support on `/live/`, a body limit at least as large as
   your upload limit, and, with Plane AI, the `/pi/` routes. We haven't tested Application Gateway for Containers with
   Azure CNI Overlay, so check Microsoft's documentation. Plane trusts the pod range (`192.168.0.0/16`) as its proxy: with
   a controller outside the cluster, Plane may not see clients' real IPs.
4. **Apply the routes:**
   ```bash
   kubectl -n plane apply -f plane-routes.yaml
   ```
   Repeat steps 3 and 4 after every Plane upgrade.

## 9. Sign in and activate your licence

1. Open `https://<your domain>` and complete the setup: create the first admin account and your workspace.
2. Activate your Plane licence key, following the activation steps in Plane's documentation.
3. Configure outgoing email (SMTP), single sign-on and AI providers in the instance admin panel at
   `https://<your domain>/god-mode/`. Plane AI reads its keys from the secrets you stored in section 5 instead. If an
   external service only accepts known addresses, allow the cluster's egress IP (`terraform output nat_public_ip`).

**Inbound email:** once the A and MX records resolve, mail sent to your intake addresses becomes work items. The email
load balancer accepts mail from any sender on ports 25, 465 and 587, as a mail server must.

## 10. Day-2 operations

Always change the installation through `terraform.tfvars`, then `terraform plan` and `terraform apply`. Review the plan
before applying. To use kubectl from a new machine, run `eval "$(terraform output -raw configure_kubectl)"`. To give
someone else access, add their object ID to `cluster_admin_object_ids`.

| Task | How |
|---|---|
| Upgrade Plane | Use the new module release: `git fetch && git checkout <new-release-tag>`, then plan and apply. Read the release notes first. Migrations and search indexes run automatically. To pick a version yourself, set `plane_version` and `chart_version`. Path B: regenerate and re-apply your routes. |
| More capacity | Raise the node limit (`node_pool = { max_count = 6 }`); the cluster autoscaler adds nodes when pods need room. Add Plane replicas through `plane_values`, for example `plane_values = "services: { api: { replicas: 4 }, worker: { replicas: 4 } }"`. All file traffic passes through the api, so scale it with your uploads and downloads. |
| Kubernetes upgrades | AKS applies patch versions and node images automatically; the module sets no maintenance window. For a new minor version, check `az aks get-versions --location <region>`, raise `kubernetes_version` one minor at a time, then plan and apply. Plane's api, worker, web and live run two replicas and stay up; RabbitMQ and OpenSearch restart briefly when their node is replaced. |
| Renew your certificate (A.2, email) | Import a new version under the same name: `az keyvault certificate import --vault-name <vault> --name plane-web --file fullchain-and-key.pem`. Plane picks it up within an hour. Path A.1 renews automatically. |
| Secrets | The module's vault holds `plane-db`, `plane-redis`, `plane-rabbitmq`, `plane-opensearch` and `plane-app-keys` (`terraform output key_vault_uri`). |
| Rotate the RabbitMQ or OpenSearch password | They're generated once and Terraform never changes them, because the servers read them only at first boot. To rotate one, follow the steps in the module README ("Things to know"). |
| Rotate AI provider keys | Add a new version of the key's secret (`az keyvault secret set --vault-name <vault> --name plane-openai-key --value "<new-key>"`; for a JSON secret, set the whole JSON again). Plane picks it up within an hour and restarts the Plane AI services. Plane AI keeps the embedding key in the OpenSearch connector it created, so a new embedding key also needs that connector updated. |

**Never change** `name` or `domain` after installation, and never delete or change the `plane-app-keys` secret: Plane
uses those keys to encrypt data, and the licence is bound to the domain.

### Rotating the Redis access key

Plane uses the cache's primary access key, which Terraform reads from Azure and writes to Key Vault. Plane can't connect
to Redis until the last step finishes, so choose a quiet time.

```bash
az redisenterprise database regenerate-key --key-type Primary --resource-group <resource-group> \
  --cluster-name "$(az redisenterprise list --resource-group <resource-group> --query '[0].name' -o tsv)"
terraform apply   # the plan should update the Key Vault secret plane-redis
kubectl -n plane annotate externalsecret plane-redis force-sync=$(date +%s) --overwrite   # Reloader restarts the apps
```

### Backups

| Data | What protects it | Limits |
|---|---|---|
| PostgreSQL | Automatic backups with point-in-time restore over `postgres.backup_retention_days` (14 by default) | A restore always creates a **new** server, without high availability, and doesn't overwrite the old one. Talk to Plane support before you switch an installation to a restored server. Azure's backup files can't be exported: for a copy you keep, use `pg_dump` (section 11) |
| Redis | An RDB snapshot every 12 hours (`redis.persistence`) | Azure restores it to the same cache by itself after a failure. It isn't a backup: you can't download or import the file, and it needs high availability on. Azure keeps only the latest snapshot |
| Blob uploads | Versioning, and soft delete for blobs and containers (`storage.soft_delete_retention_days`, 7 by default) | See below. None of this outlasts deleting the storage account |
| RabbitMQ, OpenSearch | Disk snapshots you take | See below |

**How old file versions expire.** With `storage.versioning_enabled` (the default), a policy deletes previous versions of
a file 30 days after they were created. Soft delete then keeps them for `storage.soft_delete_retention_days`.

- Azure counts from when that version was **first written**, not from when it was replaced, as AWS and GCP do. A file
  written 40 days ago and overwritten today has a previous version already past 30 days, so the next run removes it.
- A new or changed policy can take up to 24 hours to start. We haven't yet seen it run on an account with no public
  access. Azure's documentation lists no restriction for this, and the account allows trusted Azure services, but check
  that old versions are going away after your first 30 days.

### RabbitMQ and OpenSearch

Both run as a single instance in the `plane` namespace, each on its own zone-redundant disk in the AKS node resource
group. Snapshot those disks regularly. Find them:

```bash
kubectl -n plane get pvc
kubectl get pv -o custom-columns=CLAIM:.spec.claimRef.name,DISK:.spec.csi.volumeHandle
```

The `DISK` column is the disk's Azure resource ID. Snapshot each one (on a schedule of your own) into a resource group
outside this deployment: AKS deletes the node resource group with the cluster, and a snapshot in the deployment's
resource group stops `terraform destroy` from deleting that group.

```bash
az snapshot create --resource-group <your-snapshots-rg> --name <snapshot-name> --source <disk-id> --incremental true
```

- **OpenSearch** holds the search indexes, which Plane builds from the database. If its data is lost, re-create and
  re-fill them:
  ```bash
  kubectl -n plane exec deploy/plane-api-wl -- python manage.py manage_search_index index create
  kubectl -n plane exec deploy/plane-api-wl -- python manage.py manage_search_index document index --force
  ```
  When a Plane release's notes ask you to update the search mappings, run the commands they give in the same way.
- **RabbitMQ** holds Plane's background tasks while they wait to run.

### Growing the RabbitMQ or OpenSearch disk

`rabbitmq.volume_size_gb`, `opensearch.volume_size_gb` and `persistent_volume_sku` apply at the first install only: they
go into the StatefulSets' volume claim templates, which Kubernetes doesn't allow to change, so changing them later makes
the apply fail (section 12). To grow a disk, snapshot it, **leave `volume_size_gb` unchanged**, and resize its claim. The
module's storage class allows this. For RabbitMQ the claim is `pvc-plane-rabbitmq-vol-plane-rabbitmq-wl-0`:

```bash
kubectl -n plane patch pvc pvc-plane-opensearch-vol-plane-opensearch-wl-0 \
  -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'
```

Watch `CAPACITY` in `kubectl -n plane get pvc`; `kubectl -n plane describe pvc <pvc>` shows any problem. Disks can only
grow. Terraform and Helm don't see the change: later upgrades keep the larger disk.

### Changing the load balancer scheme (path A)

`ingress.scheme` is chosen at the first install. Changing it in place can fail with `PublicIPAddressInUse`, because the
web public IP would change while Traefik's load balancer is still being moved. To switch, in two applies with Plane
unreachable in between:

1. Set `ingress = { mode = "none" }` and apply. Traefik, Plane's routes and the web IP are removed. If releasing the IP
   fails, wait and apply again.
2. Set `mode = "automated"` with the new `scheme` (internal needs your own certificate, path A.2) and apply. Then point
   your domain's A record at the new IP (section 7).

## 11. Removing the installation

This deletes Plane and all its data.

**Back up first.** Unlike Plane's AWS and GCP modules, there is no final backup to fall back on: Azure Database for
PostgreSQL Flexible Server has no setting that takes one when the server is deleted.

**What Azure may still recover.** Don't plan around either of these:

- *PostgreSQL:* [Microsoft says](https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/how-to-restore-deleted-server)
  it keeps a deleted server's backup for five days and that restoring it "isn't always guaranteed". It's a REST API call
  from the same subscription, and this VNet-integrated server would also need a delegated subnet and private DNS zone,
  which `terraform destroy` removes. Its [backup FAQ](https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/concepts-backup-restore#frequently-asked-questions)
  separately says that deleting a server deletes its backups for good.
- *Uploads:* a deleted storage account
  [may be recoverable](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-recover) within 14 days, on
  a best-effort basis. Its resource group must exist, and private endpoints aren't recreated.

1. **Save the database.** It accepts connections only from inside the VNet, so run `pg_dump` from a temporary pod. Use
   the image matching `postgres.engine_version`, and allow for the pod's disk space on a large database:
   ```bash
   kubectl -n plane run pg-backup --image=postgres:15 --restart=Never --env=PGSSLMODE=require --env=PGUSER=plane \
     --env="PGHOST=$(terraform output -raw postgres_endpoint)" \
     --env="PGPASSWORD=$(kubectl -n plane get secret plane-db -o jsonpath='{.data.password}' | base64 -d)" \
     --command -- sleep 86400
   kubectl -n plane wait --for=condition=Ready pod/pg-backup --timeout=5m
   for db in plane plane_pi; do
     kubectl -n plane exec pg-backup -- pg_dump --format=custom --file=/tmp/$db.dump $db
     kubectl -n plane cp pg-backup:/tmp/$db.dump ./$db.dump
   done
   kubectl -n plane delete pod pg-backup
   ```
   Check that both dump files are complete before you continue, for example with `pg_restore --list plane.dump`.
2. **Save Plane's app keys**, somewhere safe. Plane encrypts data with them, so a restored database needs them:
   ```bash
   VAULT=$(terraform output -raw key_vault_uri | sed -E 's#https://([^.]+).*#\1#')
   az keyvault secret show --vault-name "$VAULT" --name plane-app-keys --query value -o tsv > plane-app-keys.json
   ```
3. **Save your uploads.** The account has no public endpoint, so run AzCopy on a machine that can reach its private
   endpoint, such as a VM in the VNet (delete it before step 6). You need *Storage Blob Data Reader* on the account, which
   the module doesn't grant. Use your `storage.container_name` if you changed it:
   ```bash
   azcopy login
   azcopy copy "https://$(terraform output -raw storage_account_name).blob.core.windows.net/uploads" ./uploads --recursive
   ```
4. **Path B only:** delete your routes and your ingress controller first, so its load balancer is removed
   (`kubectl -n plane delete -f plane-routes.yaml`, then uninstall the controller), and delete any public IP you created
   for it. Anything left in the resource group stops the destroy.
5. **Lift the delete locks.** PostgreSQL and the storage account each carry a `CanNotDelete` lock. In `terraform.tfvars`,
   keeping your other settings for these objects:
   ```hcl
   postgres = { deletion_protection = false }
   storage  = { deletion_protection = false }
   ```
   Then `terraform apply`.

   Don't rely on these locks to stop a `terraform destroy`: Terraform manages them, so a destroy plan removes them too.
   They protect against deletes made outside Terraform, such as in the portal. Read the plan before you confirm.
6. `terraform destroy`.
7. **Check nothing is left.** AKS deletes its node resource group, including the RabbitMQ and OpenSearch disks, with the
   cluster, so `az group show --name <resource-group>-<name>-nodes` should report that the group doesn't exist.
8. Delete your DNS records.

What stays:
- **The module's Key Vault, soft-deleted**, for `key_vault.soft_delete_retention_days` (30 by default). With purge
  protection on, nobody can purge it before then (`az keyvault list-deleted` shows it).
- Your state storage account, your own Key Vault, your snapshots, and a resource group you deployed into.

You can reinstall with the same `name`: PostgreSQL, Redis, Key Vault and the storage account get a random suffix. A
reinstall generates new app keys, so talk to Plane support before restoring old data into it.

## 12. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Browser certificate warning (A.1) | The certificate isn't issued yet: DNS doesn't resolve to the load balancer, the record is proxied, or port 80 isn't reachable from the internet | Check the record (`dig <domain>`), make it DNS-only, then `kubectl -n plane describe certificate plane-tls` and `kubectl -n plane get challenges` |
| Browser certificate warning (A.2) | The certificate in Key Vault lacks the full chain or doesn't cover the domain | Check the certificate, then `kubectl -n plane describe externalsecret plane-web-tls` |
| `helm_release` fails with `Forbidden` or a 403 from the cluster during the apply | Azure RBAC hasn't reached the API server. The module waits 2 minutes after granting cluster admin, which may not be enough | Wait a few minutes and apply again |
| `kubelogin` not found, or Helm can't get a token | kubelogin isn't installed, or your `az login` expired | `az aks install-cli`, then `az login` |
| Terraform or kubectl can't reach the cluster | Your IP isn't in `api_server_authorized_ip_ranges` | Add your network's range. If Terraform can't reach the API to refresh, add it with `az aks update --api-server-authorized-ip-ranges` first, then match it in `terraform.tfvars` |
| An ExternalSecret isn't `SecretSynced` | External Secrets' workload identity can't read the vault yet, the vault's firewall blocks it, or a secret is missing | `kubectl -n plane describe externalsecret <name>` and `kubectl -n external-secrets logs deploy/external-secrets`. Right after the first apply, roles and the federated credential can take a few minutes to work: the error clears on its own |
| Plane AI keys don't sync (`plane-ai-providers` isn't `SecretSynced`) | A secret is missing or misnamed in your vault, the vault isn't in RBAC mode, or its firewall doesn't allow the cluster's egress IP | `kubectl -n plane describe externalsecret plane-ai-providers` and `kubectl -n plane describe secretstore key-vault-<vault>`. Allow `terraform output nat_public_ip` on the vault |
| `ForbiddenByFirewall` from Key Vault during the apply | `key_vault.allowed_ips` is set without the address Terraform runs from | Add that address to `allowed_ips` |
| `Invalid value for variable "ingress"` | Path A needs exactly one certificate source, or Let's Encrypt was combined with restricted access | Set either `acme_email` or `ingress.tls_certificate_secret_id`; with Let's Encrypt keep the load balancer internet-facing and open |
| `Invalid value for variable "redis"` | `persistence` is on with `high_availability_enabled = false`: Azure has no persistence without high availability | Keep high availability on, or also set `persistence = false` |
| `Invalid value for variable "enable_components"`, `"plane_version"` or `"pi"` | Plane AI is on without search or without both API keys, with a Plane release older than the minimum, with secrets in two vaults or another subscription, with an unsupported provider or embedding model, or with `custom` settings missing or set for a vendor | Keep `opensearch.enabled`, set both `pi.api_keys` secret IDs in one vault, raise `plane_version`, pick a supported provider and Cohere model, or set `chat_base_url` and `chat_model` only with `chat_provider = "custom"` (section 5) |
| `Warning: Check block assertion failed` (email certificate) | No email certificate given | Informational: the email service uses a self-signed certificate. Set `email.certificate_secret_id` for a trusted one |
| `MissingSubscriptionRegistration`, `QuotaExceeded` or `RequestDisallowedByPolicy` | A resource provider isn't registered, a quota is too low, or an Azure Policy assignment blocks a resource | Fix it as in section 2, then apply again |
| The load balancer has no external IP (`kubectl -n traefik get svc traefik`, `EXTERNAL-IP` pending) | An Azure Policy assignment or quota, or the cluster's identity can't use the IP | `kubectl -n traefik describe svc traefik` shows the reason in its events |
| `helm_release.plane` fails with `StatefulSet.apps "plane-rabbitmq-wl"` (or `"plane-opensearch-wl"`) `is invalid: spec: Forbidden: updates to statefulset spec for fields other than … are forbidden` | `rabbitmq.volume_size_gb`, `opensearch.volume_size_gb` or `persistent_volume_sku` was changed after the first install | Set it back to the installed value and apply again. To grow a disk, see section 10 |
| `PublicIPAddressInUse` | `ingress.scheme` or `zones` was changed after the first install, or a load balancer is still releasing the IP during a destroy | Set the value back and apply again; to change the scheme, see section 10. During a destroy, wait and run it again. Changing `zones` replaces every static public IP, so treat it as fixed |
| A RabbitMQ or OpenSearch pod stays `Pending` | Its disk can't be created, or no node has room | `kubectl -n plane describe pvc` and `kubectl -n plane describe pod <pod>`; raise the quota or `node_pool.max_count` |
| Uploads or downloads fail with 403 errors in the api logs | Plane's identity can't reach Blob yet: its role or federated credential is still taking effect, or the pod has no workload identity | Wait a few minutes. Then check `kubectl -n plane get sa plane-srv-account -o yaml` for the `azure.workload.identity/client-id` annotation, and that the pod has the label `azure.workload.identity/use: "true"` |
| Uploads fail with a 413 error | The ingress request size limit is too low. On Azure every upload passes through it | Path A: raise `ingress.traefik.maxRequestBodyBytes` in `plane_values` (20 MiB by default). Path B: raise your controller's limit. Allow at least your upload limit |
| Live collaboration doesn't connect or drops (path B) | WebSockets aren't enabled on `/live/`, or the load balancer's idle timeout cuts them | Enable WebSocket support for that path, and set the idle timeout annotation (section 8) |
| No inbound email | The A or MX record for the email domain is missing or wrong | `dig MX <email domain>` must return the email domain, and `dig <email domain>` the email load balancer's IP |
| `ScopeLocked` | A delete lock is still on during a destroy (section 11, step 5). Or you turned off `storage.versioning_enabled`: the storage account's lock also covers the policy that deletes old versions | For versioning, set `storage = { versioning_enabled = false, deletion_protection = false }` and apply, then turn `deletion_protection` back on and apply |
| `terraform destroy` fails because the resource group still contains resources | Something outside Terraform is in it: your own public IP, a VM or a snapshot | Delete or move it, then run `terraform destroy` again |

For help, contact Plane support with the output of `terraform version`, the failing command's error, and
`kubectl -n plane get pods`.
