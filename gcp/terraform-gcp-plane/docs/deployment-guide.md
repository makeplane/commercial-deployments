# Deploying Plane on Google Cloud

This guide takes you from a Google Cloud project to a running Plane Commercial installation, using the
`terraform-gcp-plane` module. One `terraform apply` enables the project APIs and creates the network, a GKE cluster,
managed databases and Plane itself. You then create a few DNS records and, depending on the option you choose, finish
the ingress setup.

Plan for about two hours. Most of that is waiting for Google Cloud to create resources.

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

| Part | What | Default size |
|---|---|---|
| Project APIs | The APIs the module needs (Compute, GKE, Service Networking, Cloud SQL Admin, Memorystore, Secret Manager, IAM, Cloud Storage), enabled for you | |
| Network | A new VPC with one subnet (plus GKE's pod and service ranges), Cloud Router and Cloud NAT, private services access for Cloud SQL and Memorystore, VPC flow logs | All ranges within `10.60.0.0/15` |
| Kubernetes | GKE Standard, regional, with one node pool scaled by the cluster autoscaler | 3 × `n2d-standard-4`, one per zone (range 1–2 per zone) |
| Database | Cloud SQL for PostgreSQL 15, regional high availability, private IP only, encrypted connections only. Databases `plane` and `plane_pi` | `db-custom-2-8192` (2 vCPU, 8 GB), 100 GB SSD, grows automatically |
| Cache | Memorystore for Redis 7.2, Standard tier (a replica in another zone with automatic failover), AUTH and TLS | 4 GB |
| Message queue | RabbitMQ, **run in the cluster** | One node, 10 GiB persistent disk |
| Search | OpenSearch, **run in the cluster** | One node, 20 GiB persistent disk |
| File storage | A Cloud Storage bucket for uploads, versioned | |
| Email | Plane's email service on its own load balancer and reserved static IP, receiving mail for `intake.<your domain>` | |
| Plane | The Plane Commercial Helm chart, with its secrets in Secret Manager | |

**RabbitMQ and OpenSearch run inside the cluster.** Google Cloud has no managed service for either, so the module runs
each as a single instance on a persistent disk. You operate them: back them up with disk snapshots (section 10). If the
zone holding one of their disks is unavailable, that service is down until the zone returns. Search is optional: set
`opensearch = { enabled = false }` to turn it off.

**Plane AI is optional and off by default.** It needs an API key from an AI provider and a recent Plane release; see
[Plane AI](#plane-ai-optional) in section 5.

**Security defaults:**
- The nodes have no public IPs. Only the load balancers and the Kubernetes API endpoint are public. The API endpoint is
  open to all addresses by default: limit it to your networks with `master_authorized_networks`.
- Cloud SQL and Memorystore have private IPs only. Cloud SQL accepts only encrypted connections; Memorystore requires a
  password (AUTH) and uses TLS.
- Data is encrypted at rest with Google-managed keys. Customer-managed keys (CMEK) are not supported in this release.
- Plane reaches Cloud Storage, and External Secrets reaches Secret Manager, through GKE Workload Identity. There are no
  service account keys anywhere. Plane's identity can use the uploads bucket only; External Secrets can read only this
  installation's secrets and the certificate and AI provider secrets you name.
- The uploads bucket blocks public access. Browsers upload and download files with short-lived signed URLs.
- Passwords and keys are generated for you and stored in Secret Manager, replicated in your region only.
- GKE nodes are shielded VMs. GKE upgrades the cluster automatically within its release channel (`REGULAR`), in a
  weekend maintenance window.

Every size above can be changed in `terraform.tfvars`. For costs, enter these sizes in the Google Cloud pricing
calculator for your region.

## 2. Before you start

### Tools

| Tool | Version | Used for |
|---|---|---|
| Terraform | 1.10 or later | The deployment |
| gcloud CLI | any recent | Authentication, and the state bucket |
| `gke-gcloud-auth-plugin` | any recent | Authentication to the cluster during the apply (`gcloud components install gke-gcloud-auth-plugin`) |
| kubectl | any recent | Checking the installation |
| Helm | 3 or later | Only if you bring your own ingress (option B) |
| jq | any | Only if you store your own certificates or AI provider keys in Secret Manager |

### Google Cloud project

- **A project dedicated to Plane, with billing linked.** GKE's admin role applies to the whole project, so don't share
  it with other workloads.
- **Permissions.** The simplest is the **Owner** role on the project. A narrower set of roles that covers what the
  module creates (we haven't yet validated this list end to end; if the apply fails with a permission error, use Owner):
  `roles/serviceusage.serviceUsageAdmin`, `roles/compute.networkAdmin`, `roles/compute.securityAdmin`,
  `roles/servicenetworking.networksAdmin`, `roles/container.admin`, `roles/cloudsql.admin`, `roles/redis.admin`,
  `roles/storage.admin`, `roles/secretmanager.admin`, `roles/iam.serviceAccountAdmin`, `roles/iam.serviceAccountUser`,
  `roles/resourcemanager.projectIamAdmin`. You also need access to the Terraform state bucket (section 4).
- **APIs.** The Service Usage and Cloud Resource Manager APIs must be on. They are on in new projects; check with:
  ```bash
  gcloud services list --enabled --project <project-id> | grep -E 'serviceusage|cloudresourcemanager'
  ```
  The module enables every other API it needs. If your organisation enables APIs centrally, set `enable_apis = false`
  and have these enabled first: `compute`, `container`, `servicenetworking`, `sqladmin`, `redis`, `secretmanager`,
  `iam`, `iamcredentials`, `cloudresourcemanager` and `storage` (all `.googleapis.com`).
- **Quotas** in the region. Check these on the IAM & Admin > Quotas page:
  - N2D CPUs: at least 24. The default 3 nodes use 12, and the autoscaler can grow to 6 nodes.
  - In-use regional external IP addresses: at least 3 (web, email and Cloud NAT).
  - Persistent Disk SSD: at least 500 GB (node disks and the in-cluster RabbitMQ and OpenSearch disks).
  - Cloud SQL and Memorystore for Redis: room for one more instance of each.
- **Organisation policies.** If your project is in an organisation, check that these allow the deployment:
  - `compute.restrictLoadBalancerCreationForTypes`: allows external passthrough network load balancers
    (`EXTERNAL_NETWORK_TCP_UDP`), and internal ones (`INTERNAL_TCP_UDP`) if you use an internal load balancer.
  - `compute.restrictVpcPeering`: allows peering with Google's service networking, which Cloud SQL and Memorystore use.
  - `gcp.resourceLocations`: allows your region.
  - `gcp.restrictNonCmekServices`: must not require CMEK for Compute Engine, GKE, Cloud SQL, Memorystore, Cloud Storage
    or Secret Manager.

### Domain and DNS

- **A domain for Plane**, for example `plane.example.com`. **It can never change after installation:** your Plane licence
  is bound to it.
- **Access to the DNS zone.** You create the DNS records yourself after the apply; the module never changes your DNS.
  Any DNS provider works.
- **An email domain** for inbound email to work items. The default is `intake.<your domain>`.

### Plane licence

A Plane Commercial licence key, which you activate after installation.

## 3. Choose how traffic reaches Plane

Pick one option before you configure.

| Option | Choose it when | The module installs | You do after the apply |
|---|---|---|---|
| **A.1: Automated, Let's Encrypt** | Plane is reachable from the internet, and a free Let's Encrypt certificate is fine | Traefik ingress behind a load balancer on a reserved static IP, Plane's routes, and a Let's Encrypt certificate | Create the DNS records |
| **A.2: Automated, your certificate** | You have your own certificate, or Plane is internal only | Traefik ingress behind a load balancer on a reserved static IP, Plane's routes, and your certificate | Store the certificate in Secret Manager first; create the DNS records |
| **B: Bring your own ingress** (default) | You run your own ingress controller (NGINX, your own Traefik, GKE Gateway, …) or certificate tooling | No ingress controller and no routes | Install your controller, apply Plane's routes, add the certificate, create the DNS records |

**About A.1:** Let's Encrypt checks domain ownership over HTTP, so Plane must be reachable from the whole internet on
port 80. The certificate is issued a few minutes after your DNS record points at the load balancer, and it renews
automatically. If you need to restrict who can reach Plane, choose A.2 or B.

**Email certificate (any option):** the email service uses a certificate for encrypted mail. If you don't provide one,
it generates a self-signed certificate. That's fine for receiving mail from other mail servers. To use a trusted one,
store it in Secret Manager (next section) and set `email.certificate_secret`.

### Storing a certificate in Secret Manager (A.2 and email)

Store each certificate as a secret whose value is JSON with two keys: `tls.crt` (the full chain, PEM) and `tls.key`
(the private key, PEM).

- Create it in the **same project** as Plane (`project_id`), as a regular secret. Regional secrets (created with
  `--location`) are not supported.
- Refer to it in `terraform.tfvars` as `projects/<project-id>/secrets/<secret-name>`.
- One certificate can serve both web and email if it lists both names, for example `plane.example.com` and
  `intake.plane.example.com`.

```bash
jq -n --rawfile crt fullchain.pem --rawfile key privkey.pem '{"tls.crt": $crt, "tls.key": $key}' |
  gcloud secrets create plane-web-tls --project <project-id> \
    --replication-policy user-managed --locations <region> --data-file=-
```

The module lets External Secrets read only the secrets you name. To renew later, add a new version of the secret
(section 10): it's picked up within an hour.

## 4. Set up Terraform state

Terraform state contains generated passwords and keys, so keep it in a private, versioned Cloud Storage bucket that only
the people and pipelines who deploy Plane can access.

```bash
gcloud storage buckets create gs://<state-bucket> --project <project-id> --location <region> \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update gs://<state-bucket> --versioning
```

Optionally, delete old state versions after a while:

```bash
cat > lifecycle.json <<'EOF'
{"rule": [{"action": {"type": "Delete"}, "condition": {"daysSinceNoncurrentTime": 90}}]}
EOF
gcloud storage buckets update gs://<state-bucket> --lifecycle-file=lifecycle.json
```

The bucket is encrypted by default, and Terraform's GCS backend locks the state natively, so two applies can't run at
once. You can also use an existing bucket that meets these requirements, with its own prefix for Plane.

## 5. Configure

Sign in with gcloud. Terraform uses the application default credentials, and the cluster plugin uses your gcloud
login:

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project <project-id>
```

Get the module at the release you were given:

```bash
git clone https://github.com/makeplane/commercial-deployments.git
cd commercial-deployments
git checkout <release-tag>
cd gcp/terraform-gcp-plane/examples/complete
```

Point Terraform at your state bucket:

```bash
cp backend.hcl.example backend.hcl
```

```hcl
# backend.hcl
bucket = "<state-bucket>"
prefix = "plane"
```

Create your settings file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` is the only file you edit. `terraform.tfvars.example` lists every setting with its default. Set the
required values and the block for your option:

```hcl
project_id = "my-plane-project"
region     = "us-central1"
name       = "plane"             # prefix for all resources, 3–20 characters; never change it
domain     = "plane.example.com" # never change it

# Who can reach the Kubernetes API (Terraform needs it during the apply). Use your network's ranges.
master_authorized_networks = ["203.0.113.0/24"]

# Option A.1: Let's Encrypt
ingress    = { mode = "automated" }
acme_email = "ops@example.com" # Let's Encrypt account email, for expiry notices

# Option A.2: your certificate (instead of the A.1 lines)
# ingress = { mode = "automated", tls_certificate_secret = "projects/my-plane-project/secrets/plane-web-tls" }

# Option B: bring your own ingress. Set nothing here.

# Optional: your email certificate (any option)
# email = { certificate_secret = "projects/my-plane-project/secrets/plane-mail-tls" }
```

**Common optional settings.** For objects, set only the fields you change.

| Setting | Example | Effect |
|---|---|---|
| Restrict who reaches Plane (A.2) | `ingress = { mode = "automated", tls_certificate_secret = "…", allowed_cidrs = ["10.0.0.0/8"] }` | The load balancer accepts only these ranges |
| Internal load balancer (A.2) | `ingress = { …, scheme = "internal" }` | Plane gets an IP from the module's subnet, reachable only from the VPC or connected networks |
| More nodes | `node_pool = { max_per_zone = 3 }` | The autoscaler can grow to 3 nodes per zone (9 in all) |
| Choose the zones | `zones = ["us-central1-a", "us-central1-b", "us-central1-c"]` | Nodes run in these zones instead of three GKE picks |
| Larger database | `postgres = { tier = "db-custom-4-16384" }` | 4 vCPUs and 16 GB |
| Larger cache | `redis = { memory_size_gb = 8 }` | 8 GB |
| Larger search disk | `opensearch = { volume_size_gb = 50 }` | 50 GiB for OpenSearch |
| No search | `opensearch = { enabled = false }` | No OpenSearch; Plane runs with search indexing off, so search is more limited |
| Different email domain | `email = { smtp_domain = "mail.example.com" }` | Intake addresses use this domain |
| Email without a public endpoint | `email = { load_balancer = false }` | The email service runs, but can't receive mail from the internet |
| No email | `email = { enabled = false }` | No email service and no email load balancer |
| Different network ranges | `network = { subnet_cidr = "10.80.0.0/20", … }` | Avoids overlap with networks you peer or connect with |
| Extra admins | `cluster_admin_members = ["group:platform@example.com"]` | GKE admin role on the project for these users or groups |
| Labels | `labels = { cost-center = "1234" }` | Added to every resource that supports labels |

When an object setting appears twice (for example two `email = { … }` lines), Terraform fails: combine the fields
into one line.

### Plane AI (optional)

Plane AI runs on the same uploads bucket and in-cluster OpenSearch as Plane. It needs:

- **Plane** at the first release whose Plane AI supports Cloud Storage (named in the module's release notes), and the
  Plane Commercial Helm chart **3.11.6 or later** (the default). The module refuses Plane AI with an older
  `plane_version`.
- **Search on** (`opensearch.enabled`, the default). With Plane AI, OpenSearch gets a larger memory allowance (1.5 GB
  heap, 3 GiB limit).
- **Two API keys:** OpenAI for chat and Cohere for embeddings (semantic search), each stored in Secret Manager before
  the apply. The module refuses Plane AI without both keys.

**1. Store the provider keys.** Create two secrets in the **same project** as Plane (`project_id`), each holding only
the key, as plain text:

```bash
printf %s "<openai-key>" | gcloud secrets create plane-openai-key --project <project-id> \
  --replication-policy=user-managed --locations=<region> --data-file=-
printf %s "<cohere-key>" | gcloud secrets create plane-cohere-key --project <project-id> \
  --replication-policy=user-managed --locations=<region> --data-file=-
```

The keys go straight to Secret Manager: they never appear in `terraform.tfvars` or the Terraform state. The module
lets External Secrets read these two secrets and copies them into the cluster.

**2. Turn Plane AI on** in `terraform.tfvars`:

```hcl
enable_components = { pi = true }
pi = {
  api_keys = {
    chat_key_secret      = "projects/my-plane-project/secrets/plane-openai-key"
    embedding_key_secret = "projects/my-plane-project/secrets/plane-cohere-key"
  }
}
# plane_version = "<a release with Plane AI on Cloud Storage>" # if the module's default is older
```

**Other providers.** For Anthropic chat, store the Anthropic key instead and set `chat_provider = "anthropic"`. For
OpenAI embeddings, set `embedding_model = "openai/text-embedding-3-small"` (or `openai/text-embedding-ada-002`); with
OpenAI chat too, use the same secret for both keys. Only these 1536-dimension embedding models are accepted, because
Plane's page search uses the same index size. Choose the embedding model before you turn Plane AI on: changing it
later means recreating Plane AI's indexes.

**Outbound access.** Plane AI calls your providers' APIs over the internet through the module's Cloud NAT: the Plane AI
pods call the language model, and the OpenSearch pod calls the embedding API. If your organisation restricts outbound
traffic, allow HTTPS to the providers you use, for example `api.cohere.ai`, `api.openai.com` and `api.anthropic.com`.

## 6. Deploy

```bash
terraform init -backend-config=backend.hcl
terraform plan -out plane.tfplan
```

Check that the plan only adds resources: `Plan: N to add, 0 to change, 0 to destroy`. Then apply:

```bash
terraform apply plane.tfplan
```

As an estimate, the apply takes 45–75 minutes. Creating the cluster, Cloud SQL and Memorystore takes most of it, and
the database migrations take about 20 minutes on a new installation, so the last step (`helm_release.plane`) runs for a
while without output. That's expected.

When it finishes, connect kubectl to the cluster:

```bash
$(terraform output -raw configure_kubectl)
kubectl -n plane get pods             # all Running or Completed
kubectl -n plane get externalsecrets  # all SecretSynced
```

## 7. Create the DNS records

```bash
terraform output dns_records
```

| Record | Name | Type | Value |
|---|---|---|---|
| Web (options A.1 and A.2) | your `domain` | A | the `web` value: the load balancer's static IP |
| Web (option B) | your `domain` | A | your own ingress controller's load balancer IP |
| Email host | your email domain (`intake.<domain>`) | A | the `email_host` value: the email load balancer's static IP |
| Email | your email domain (`intake.<domain>`) | MX | the `email_mx` value: `10 <email domain>` |

- The IPs are static addresses reserved by the module: they don't change while the installation exists, so A records
  are safe. They also work at a zone apex.
- An MX record can't point at an IP, so the email domain gets both an A record and an MX record naming itself.
- With `ingress.scheme = "internal"`, the web IP is private: create the record in a DNS zone your users resolve, for
  example a private zone.
- If your DNS is on Cloudflare, set the records to **DNS only** (no proxy).

## 8. Finish the ingress setup

### Option A.1

The certificate is issued a few minutes after the web DNS record resolves. Until then, browsers show a certificate
warning. Check progress:

```bash
kubectl -n plane get certificate plane-tls   # READY becomes True
kubectl -n plane get challenges               # empty once issued
```

### Option A.2

Nothing more to do. To check the certificate was loaded from Secret Manager:

```bash
kubectl -n plane get externalsecret plane-web-tls   # STATUS SecretSynced
```

### Option B

1. **Install your ingress controller** if it isn't already in the cluster. On GKE, a controller whose Service has
   `type: LoadBalancer` gets a Google Cloud load balancer automatically. Reserve a static IP for it if you can, so your
   DNS record never has to change.
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

   **Other controllers** (GKE Gateway and others): use the generated NGINX Ingress as the route table: each path, the
   service and port it goes to. Plane needs WebSocket support on `/live/` and an upload size limit of at least 20 MB.
4. **Apply the routes:**
   ```bash
   kubectl -n plane apply -f plane-routes.yaml
   ```
   Repeat steps 3 and 4 after every Plane upgrade.

## 9. Sign in and activate your licence

1. Open `https://<your domain>` and complete the setup: create the first admin account and your workspace.
2. Activate your Plane licence key, following the activation steps in Plane's documentation.
3. Configure outgoing email (SMTP), single sign-on and AI providers in the instance admin panel at
   `https://<your domain>/god-mode/`. Plane AI reads its keys from the secret you stored in section 5 instead.

**Inbound email:** once the A and MX records resolve, mail sent to your intake addresses becomes work items. The email
load balancer accepts mail from any sender on ports 25, 465 and 587, as a mail server must.

## 10. Day-2 operations

Always change the installation through `terraform.tfvars`, then `terraform plan` and `terraform apply`. Review the plan
before applying.

| Task | How |
|---|---|
| Upgrade Plane | Use the new module release: `git fetch && git checkout <new-release-tag>`, then plan and apply. Read the release notes first. Migrations and search indexes run automatically. To pick a version yourself, set `plane_version` (and `chart_version`, 3.11.6 or later). Option B: regenerate and re-apply your routes. |
| More capacity | Raise the node limit (`node_pool = { max_per_zone = 3 }`); the GKE cluster autoscaler adds nodes when pods need room. Add Plane replicas through `plane_values`, for example `plane_values = "services: { api: { replicas: 4 }, worker: { replicas: 4 } }"`. |
| Kubernetes upgrades | Automatic, within the release channel (`release_channel`, default `REGULAR`), on Saturdays and Sundays between 02:00 and 08:00 UTC. Nodes are replaced one at a time. Plane's api, worker, web and live run two replicas and stay up; RabbitMQ and OpenSearch restart briefly when their node is replaced. |
| Renew your certificate (A.2, email) | Add a new version of the secret (below). Plane picks it up within an hour. Option A.1 renews automatically. |
| Backups | Cloud SQL keeps the last 14 daily backups and 7 days of logs for point-in-time recovery. The uploads bucket keeps old versions of files for 30 days. Back up RabbitMQ and OpenSearch with disk snapshots (below). |
| Secrets | Database, cache, RabbitMQ and OpenSearch credentials and Plane's app keys are in Secret Manager as `<name>-plane-*` (`terraform output secret_ids`). |
| Rotate AI provider keys | Add a new version of the key's secret (`printf %s "<new-key>" \| gcloud secrets versions add plane-openai-key --project <project-id> --data-file=-`). Plane picks it up within an hour and restarts the Plane AI services. Plane AI keeps the embedding key in the OpenSearch connector it created, so a new embedding key also needs that connector updated. |

**Never change** `name` or `domain` after installation, and never delete or change the `<name>-plane-app-keys` secret:
Plane uses those keys to encrypt data, and the licence is bound to the domain.

### Renewing a certificate

```bash
jq -n --rawfile crt fullchain.pem --rawfile key privkey.pem '{"tls.crt": $crt, "tls.key": $key}' |
  gcloud secrets versions add plane-web-tls --project <project-id> --data-file=-
```

Plane always reads the latest version. Traefik reloads the web certificate, and the email service restarts
automatically to use a new email certificate.

### RabbitMQ and OpenSearch

Both run as a single instance in the `plane` namespace, each on its own persistent disk. Snapshot those disks regularly.
Find them:

```bash
kubectl -n plane get pvc
kubectl get pv -o custom-columns=CLAIM:.spec.claimRef.name,DISK:.spec.csi.volumeHandle
```

The `DISK` column reads `projects/<project>/zones/<zone>/disks/<disk>`. Snapshot each disk:

```bash
gcloud compute snapshots create <snapshot-name> --source-disk <disk> --source-disk-zone <zone> --project <project-id>
```

For automatic snapshots, create a snapshot schedule (`gcloud compute resource-policies create snapshot-schedule`) and
attach it to both disks (`gcloud compute disks add-resource-policies`).

- **OpenSearch** holds the search indexes, which Plane builds from the database. If its data is lost, re-create and
  re-fill them:
  ```bash
  kubectl -n plane exec deploy/plane-api-wl -- python manage.py manage_search_index index create
  kubectl -n plane exec deploy/plane-api-wl -- python manage.py manage_search_index document index --force
  ```
  When a Plane release's notes ask you to update the search mappings, run the commands they give in the same way.
- **RabbitMQ** holds Plane's background tasks while they wait to run.
- Disk sizes are `rabbitmq.volume_size_gb` and `opensearch.volume_size_gb`.

### Redis TLS

Memorystore uses TLS by default (`redis.transit_encryption = true`, port 6378), and Plane trusts its server certificate
automatically. To use the private network with the AUTH password only, set `redis = { transit_encryption = false }`.
Decide before the first apply if you can: Memorystore sets in-transit encryption only when it creates an instance, so
changing it later replaces the cache (check the plan), and Plane reconnects to the new one during the apply.

## 11. Removing the installation

This deletes Plane and all its data.

1. **Option B only:** delete your routes and your ingress controller first, so its load balancer is removed
   (`kubectl -n plane delete -f plane-routes.yaml`, then uninstall the controller). A leftover load balancer or its
   firewall rules stop the VPC from being deleted.
2. **Note the disks** of the in-cluster RabbitMQ and OpenSearch (the `DISK` column in section 10). They outlive the
   cluster, and you delete them in step 6.
3. Turn off the database's deletion protection, and allow deleting the uploads bucket with its files. Without these,
   `terraform destroy` stops with an error. In `terraform.tfvars`:
   ```hcl
   postgres             = { deletion_protection = false }
   bucket_force_destroy = true
   ```
   Then `terraform apply`.
4. **Keep a copy of the database if you may need it.** Deleting the Cloud SQL instance also deletes its automated
   backups. Export the data first (`gcloud sql export sql`, see Cloud SQL's documentation).
5. `terraform destroy`.
6. Delete the persistent disks you noted:
   ```bash
   gcloud compute disks list --project <project-id> --filter="name~^pvc-"
   gcloud compute disks delete <disk> --zone <zone> --project <project-id>
   ```
7. Delete your DNS records.

What stays:
- The project APIs the module enabled (other resources in the project may use them).
- Your state bucket, and your certificate and AI provider secrets in Secret Manager.
- The disk snapshots you took.

You can reinstall with the same `name`: the Cloud SQL instance and the uploads bucket get a random suffix, so Cloud
SQL's week-long reservation of deleted instance names doesn't block you.

## 12. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Browser certificate warning (A.1) | The certificate isn't issued yet: DNS doesn't resolve to the load balancer, the record is proxied, or port 80 isn't reachable from the internet | Check the record (`dig <domain>`), make it DNS-only, then `kubectl -n plane describe certificate plane-tls` and `kubectl -n plane get challenges` |
| Browser certificate warning (A.2) | The certificate secret has the wrong keys or doesn't cover the domain | Keys must be `tls.crt` and `tls.key`; `kubectl -n plane describe externalsecret plane-web-tls` |
| An ExternalSecret isn't `SecretSynced` | The secret doesn't exist in `project_id`, has no version, or isn't JSON with the expected keys (the AI provider keys are plain text) | `kubectl -n plane describe externalsecret <name>`. Right after the first apply, Workload Identity can take a minute or two to work: the error clears on its own |
| `Invalid value for variable "ingress"` | Option A needs exactly one certificate source, or Let's Encrypt was combined with restricted access | Set either `acme_email` or `ingress.tls_certificate_secret`; with Let's Encrypt keep the load balancer internet-facing and open |
| `Invalid value for variable "enable_components"`, `"plane_version"` or `"pi"` | Plane AI is on without search or without both API keys, with a Plane release older than the minimum, a secret in another project, or an unsupported provider or embedding model | Keep `opensearch.enabled`, set both `pi.api_keys` secrets (one secret when OpenAI does both), raise `plane_version`, or pick a supported provider and model (section 5) |
| `Warning: Check block assertion failed` (email certificate) | No email certificate given | Informational: the email service uses a self-signed certificate. Set `email.certificate_secret` for a trusted one |
| Apply fails because an API "has not been used in project … or it is disabled" | A newly enabled API wasn't ready yet, or `enable_apis = false` and the API is off | Wait a few minutes and apply again, or enable the API (section 2) |
| Apply fails with `Insufficient regional quota` or `QUOTA_EXCEEDED` | Quota too low (often N2D CPUs or external IPs) | Raise the quota (section 2) and apply again |
| Apply fails with `Constraint constraints/… violated` | An organisation policy blocks a resource | Ask your organisation admin to allow it for this project (section 2) |
| `terraform plan` can't reach the cluster, or `gke-gcloud-auth-plugin` not found | Your IP isn't in `master_authorized_networks`, or the plugin isn't installed | Add your network's range and apply; install the plugin (section 2) and run `gcloud auth login` |
| `helm_release.plane` runs for a long time | Database migrations on a new installation (about 20 minutes) | Wait; check with `kubectl -n plane get pods` |
| The load balancer has no external IP (`kubectl -n traefik get svc traefik`, `EXTERNAL-IP` pending) | An organisation policy blocks the load balancer type, or quota | `kubectl -n traefik describe svc traefik` shows the reason in its events |
| A RabbitMQ or OpenSearch pod stays `Pending` | Its disk can't be created (SSD quota) or no node has room | `kubectl -n plane describe pvc` and `kubectl -n plane describe pod <pod>`; raise the quota or `node_pool.max_per_zone` |
| Uploads fail with a CORS error in the browser | Plane was opened on a hostname other than `domain`; the bucket accepts only `https://<domain>` | Use the configured domain |
| Uploads fail (option B) | Your controller's request size limit is too low | Allow at least 20 MB |
| Live collaboration doesn't connect (option B) | WebSockets not enabled on `/live/` | Enable WebSocket support for that path |
| No inbound email | The A or MX record for the email domain is missing or wrong | `dig MX <email domain>` must return the email domain, and `dig <email domain>` the email load balancer's IP |
| `terraform destroy` fails on the Cloud SQL instance or the bucket | Deletion protection is on, or the bucket isn't empty | Section 11, step 3 |
| `terraform destroy` fails releasing a static IP or deleting the VPC | A load balancer was still being removed, or your own (option B) is still there | Remove your controller (section 11), wait a few minutes and run `terraform destroy` again |

For help, contact Plane support with the output of `terraform version`, the failing command's error, and
`kubectl -n plane get pods`.
