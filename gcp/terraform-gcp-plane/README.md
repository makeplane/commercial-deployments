# terraform-gcp-plane

Terraform module that deploys [Plane](https://plane.so) Commercial on Google Cloud with one `terraform apply`: the
project APIs, the network, a GKE cluster, managed data services and Plane itself (the `plane-enterprise` Helm chart).

> **Status:** tested end to end on GKE (apply, app checks, destroy) with a preview build of the chart. It needs
> plane-enterprise chart **3.11.7** (pending release: from 3.11.6 the bundled RabbitMQ reads its credentials from
> External Secrets; 3.11.7 sets the OpenSearch heap for Plane AI). Until it's published, reference it from this
> repository.

## What it creates

| Layer | Resources | Defaults |
|---|---|---|
| Project | Enables the APIs the module needs (Compute, GKE, Service Networking, Cloud SQL Admin, Memorystore, Secret Manager, IAM, Cloud Storage); left on at destroy | `enable_apis = true` |
| Network | VPC, one subnet with GKE's pods and services ranges, Cloud Router + Cloud NAT, private services access (Cloud SQL, Memorystore), flow logs | All ranges in 10.60.0.0/15; no firewall rules of its own (GKE creates what it needs) |
| Cluster | GKE Standard, regional, private nodes, Workload Identity, Dataplane V2, shielded nodes, release channel, maintenance window; one node pool with the cluster autoscaler; a node service account with `roles/container.defaultNodeServiceAccount` only | REGULAR channel, `n2d-standard-4`, 3 zones × 1–2 nodes, 50 GB pd-balanced |
| PostgreSQL | Cloud SQL for PostgreSQL, databases `plane` and `plane_pi`, user `plane` | 15, `db-custom-2-8192`, regional HA, 100 GB SSD (autoresize), private IP only, TLS required, backups 14 + PITR, deletion protection |
| Cache | Memorystore for Redis | 7.2, STANDARD_HA, 4 GB, AUTH, TLS (`redis.transit_encryption`) |
| Queue | RabbitMQ, run in the cluster by the chart (GCP has no managed RabbitMQ) | One node, 10 GiB `standard-rwo` disk; generated credentials in Secret Manager |
| Search | OpenSearch, run in the cluster by the chart, `opensearch.enabled` | On: one node, 20 GiB `standard-rwo` disk; generated credentials in Secret Manager |
| Email | Plane's email service (inbound email to work items) on its own passthrough load balancer on a reserved static IP | On by default: ports 25/465/587, sender IP preserved, receiving mail for `intake.<domain>`; you create the A and MX records |
| Storage | GCS uploads bucket | Uniform access, public access prevention, versioning, CORS for your domain |
| Secrets | Secret Manager: database, Redis AUTH, RabbitMQ, OpenSearch, app keys | Replicated in `region` only; values never pass through Terraform variables |
| Edge | **Path A** (`ingress.mode = "automated"`): Traefik behind a passthrough load balancer on a reserved static IP, Plane's routes, certificates (Let's Encrypt HTTP-01 or yours from Secret Manager). **Path B** (default): none; you bring your ingress | The module configures no DNS: you create the records (`dns_records` output) |
| In cluster (Helm) | External Secrets, Reloader, **plane-enterprise**; path A also Traefik and (with Let's Encrypt) cert-manager | Pods reach GCS and Secret Manager through **GKE Workload Identity**: no service-account keys |
| Plane workloads | web, space, admin, api, worker, beat-worker, live, live-exporter, silo, drawio, plus the services paid features need: outbox-poller, automation-consumer, runner (Automations), agent-consumer, webhook-consumer, iframely (link previews), worker-importers (imports, on their own queue), email | api, worker, web and live run 2 replicas spread across nodes, with PodDisruptionBudgets; the rest 1. Plane AI (pi) off by default (`enable_components.pi`, see [Plane AI](#plane-ai)). Any attachment type can be uploaded, as today |

## Usage

```hcl
provider "google" {
  project = "my-plane-project"
  region  = "us-central1"
}

provider "helm" {
  kubernetes = {
    host                   = module.plane.cluster_endpoint
    cluster_ca_certificate = base64decode(module.plane.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
    }
  }
}

module "plane" {
  source = "git::https://github.com/makeplane/commercial-deployments.git//gcp/terraform-gcp-plane?ref=<tag>"

  project_id = "my-plane-project"
  region     = "us-central1"
  name       = "plane"
  domain     = "plane.example.com"
  ingress    = { mode = "automated" } # path A; omit for path B (bring your own ingress)
  acme_email = "ops@example.com"      # Let's Encrypt for the web certificate
}
```

A full example is in [`examples/complete`](examples/complete). For a step-by-step installation, see the
[deployment guide](docs/deployment-guide.md).

## Prerequisites

- Terraform ≥ 1.10, the **gcloud CLI** and **`gke-gcloud-auth-plugin`** (Helm authenticates to GKE with it).
- A GCP project with billing linked, **dedicated to Plane**: GKE's admin role is project-wide. The Service Usage and
  Cloud Resource Manager APIs must be on (they are on new projects); the module enables the rest.
- Credentials allowed to enable APIs and to create networks (VPC, NAT, peering, addresses), GKE, Cloud SQL,
  Memorystore, Cloud Storage, Secret Manager, service accounts and project IAM bindings. In practice, the project's
  Owner.
- Organisation policies that allow external passthrough network load balancers
  (`compute.restrictLoadBalancerCreationForTypes`), VPC peering with `servicenetworking`
  (`compute.restrictVpcPeering`) and the region (`gcp.resourceLocations`). `gcp.restrictNonCmekServices` isn't
  supported yet (Google-managed encryption in this release).
- Network access from where you run Terraform to the GKE API endpoint. It's public by default; restrict it with
  `master_authorized_networks`.
- An **encrypted, private remote state backend** (a GCS bucket). State holds generated secrets (database, RabbitMQ and
  OpenSearch passwords, the Redis AUTH string, app keys).
- Regional quota for about 24 N2D CPUs, 3 external IPs (web, email, NAT) and 500 GB of SSD/balanced persistent disk.

## Ingress, certificates and DNS

Two paths, chosen with `ingress.mode`. **The module configures no DNS in either**: after the apply, create the records
from the `dns_records` output.

| | Path A: automated (`ingress.mode = "automated"`) | Path B: bring your own (`ingress.mode = "none"`, default) |
|---|---|---|
| Ingress controller | Traefik behind a passthrough load balancer on a reserved static IP, installed by the module | Yours (Traefik, NGINX, GKE Gateway, …), after the apply |
| Plane's routes | Created by the module | Yours: generate them from the chart (below) |
| Web certificate | **A.1** Let's Encrypt (`acme_email`, HTTP-01), or **A.2** yours from Secret Manager (`ingress.tls_certificate_secret`) | Yours |
| Email certificate | Yours from Secret Manager (`email.certificate_secret`), else self-signed | Same |
| DNS | Yours: A `domain` → `load_balancer_ip`; A `smtp_domain` → `email_load_balancer_ip`; MX `smtp_domain` → `smtp_domain` | Yours: `domain` → your ingress load balancer; the same email records |

**Path A, A.1 (Let's Encrypt):** cert-manager proves domain ownership over HTTP (HTTP-01), so Plane must be reachable
from the internet on port 80 (`ingress.allowed_cidrs` includes `0.0.0.0/0`, internet-facing; the module checks this).
The certificate is issued once your DNS record points at `load_balancer_ip`; cert-manager keeps retrying until then,
and Traefik serves its default certificate meanwhile. Renewal is automatic. Use the Let's Encrypt staging server
(`acme_server`) while testing.

**Your own certificates (A.2, and the email certificate):** store each in Secret Manager **in `project_id`** before
the apply, as a JSON secret with the keys `tls.crt` (full chain, PEM) and `tls.key`, and pass it as
`projects/<project_id>/secrets/<name>`. The module lets External Secrets read that secret (and nothing else of yours)
and copies it into the cluster; pods that mount it wait until it has. To renew, add a new secret version: it's picked
up within an hour, Traefik reloads it and the email pod restarts automatically. The same secret can serve web and email
if the certificate lists both names.

```bash
jq -n --rawfile crt fullchain.pem --rawfile key privkey.pem '{"tls.crt": $crt, "tls.key": $key}' |
  gcloud secrets create plane-web-tls --project my-plane-project --replication-policy user-managed \
    --locations us-central1 --data-file=-
```

**DNS records:** A records to the reserved static IPs. They belong to the module and don't change while it's installed
(Traefik's Service can be recreated without losing its IP). `ingress.scheme = "internal"` takes the web IP from the
module's subnet instead. An MX record can't point at an IP, so the email service needs an A record for `smtp_domain`
and an MX record naming it. Keep Cloudflare records DNS-only (no proxy): Traefik terminates TLS.

**Path B routes:** generate Plane's routes for your controller from the chart and the values the module generated
(`chart_version`, default 3.11.7; if you set `plane_values`, add it as a second `-f`). The routes serve TLS from the
Secret named by `tls_secret_name` (`plane-tls`) in namespace `plane`.

```bash
helm repo add plane https://helm.plane.so/
terraform output -raw plane_helm_values > plane-values.yaml

# Traefik (IngressRoute + its Middlewares; entry point "websecure" unless you set ingress.traefik.entryPoints)
helm template plane plane/plane-enterprise --version <chart_version> -n plane -f plane-values.yaml \
  --set ingress.enabled=true,ingress.controller=traefik \
  --show-only templates/ingress-traefik.yaml --show-only templates/traefik-middleware.yaml > plane-routes.yaml

# NGINX (standard Ingress; set your IngressClass name; NGINX's default 1 MB upload limit raised to 20 MB)
helm template plane plane/plane-enterprise --version <chart_version> -n plane -f plane-values.yaml \
  --set ingress.enabled=true,ingress.controller=nginx,ingress.ingressClass=<your-class> \
  --set-string 'ingress.ingress_annotations.nginx\.ingress\.kubernetes\.io/proxy-body-size=20m' \
  --show-only templates/ingress-nginx.yaml > plane-routes.yaml

kubectl -n plane apply -f plane-routes.yaml   # regenerate and re-apply after every Plane upgrade
```

Other controllers: use the generated NGINX Ingress as the route table (paths → services and ports). Plane needs
WebSockets on `/live/` and an upload limit of at least 20 MB.

Destroy in path B in reverse: remove your routes, then your ingress controller and its load balancer, then
`terraform destroy`.

## Search (OpenSearch)

GCP has no managed OpenSearch, so the chart runs a single OpenSearch node in the cluster (on by default, as in today's
deployments), on a 20 GiB persistent disk. Its credentials are generated, stored in Secret Manager and synced by
External Secrets into the one Secret both OpenSearch and Plane read. Set `opensearch = { enabled = false }` to run
without it: Plane then has search indexing off.

**Search indexes are created automatically:** after every install and upgrade, the chart's `plane-api-search-index`
Job waits for the database migrations and creates any missing index. Index names are
`<opensearch.index_prefix>_<name>` (prefix `plane`, as today's deployments). Changing mappings stays manual, when a
Plane release's notes ask for it:

```bash
kubectl -n plane exec deploy/plane-api-wl -- python manage.py manage_search_index list
kubectl -n plane exec deploy/plane-api-wl -- python manage.py manage_search_index index update --force   # added fields
kubectl -n plane exec deploy/plane-api-wl -- python manage.py manage_search_index index rebuild --force  # changed mappings, then:
kubectl -n plane exec deploy/plane-api-wl -- python manage.py manage_search_index document index --force
```

The in-cluster OpenSearch and RabbitMQ are yours to operate: one node each, backed up by disk snapshots.

## Email

Plane's email service turns inbound email to work items. It's **on by default with its own internet-facing passthrough
load balancer**, receiving mail for **`intake.<domain>`** (set `email.smtp_domain` for another domain):

- **Load balancer:** ports 25 SMTP, 465 SMTPS, 587 submission, on the reserved static IP `<name>-email`, with
  `externalTrafficPolicy: Local`, so the email service sees the sender's real IP (SPF). The IP is the
  `email_load_balancer_ip` output.
- **DNS records:** yours: `<smtp_domain> A <email IP>` and `<smtp_domain> MX 10 <smtp_domain>` (see `dns_records`).
  The default is a subdomain so it never collides with a record on `domain`.
- **Certificate** (STARTTLS/SMTPS): yours from Secret Manager (`email.certificate_secret`, see above); otherwise the
  email service generates a self-signed one at startup. Mail servers delivering on port 25 use opportunistic TLS and
  accept it; mail clients on 465/587 will warn. In path A with the email load balancer on, the module shows a warning
  (not an error) when it's missing.

The email load balancer is always internet-facing and open to all senders on its three ports.
`email = { load_balancer = false }` keeps the service running with no load balancer (not reachable from the internet,
like today's managed deployment); `email = { enabled = false }` turns the service and its load balancer off.

## Plane AI

Plane AI (pi) is off by default. `enable_components = { pi = true }` runs it on the same GCS bucket (keyless, through
Plane's Workload Identity: no new IAM) and the `plane_pi` database the module already creates. It needs:

- **`opensearch.enabled`** (the default): Plane AI keeps its search and embeddings in the in-cluster OpenSearch. With
  pi on, the module gives OpenSearch a 1.5 GB heap in a 3 GiB memory limit (chart 3.11.7+).
- **`plane_version`**: the first Plane release whose Plane AI supports GCS storage (named in this module's release
  notes). The module refuses older versions.
- **`plane_ai.providers_secret`**: a Secret Manager secret **in `project_id`** that you create before the apply, as
  `projects/<project_id>/secrets/<name>`. The module lets External Secrets read it and copies it into the cluster
  (`plane-ai-providers`); the keys never pass through Terraform. Its value is JSON with the provider API keys:

  | Key | Used for |
  |---|---|
  | `COHERE_API_KEY` | Embeddings with `cohere/embed-v4.0` (the default `plane_ai.embedding_model`) |
  | `OPENAI_API_KEY` | The LLM, and embeddings with `openai/text-embedding-3-small` or `openai/text-embedding-ada-002` |
  | `CLAUDE_API_KEY` | The LLM (Anthropic) |
  | `GROQ_API_KEY` | Optional: Groq models |

  ```bash
  jq -n --arg cohere "$COHERE_API_KEY" --arg claude "$CLAUDE_API_KEY" \
    '{COHERE_API_KEY: $cohere, CLAUDE_API_KEY: $claude}' |
    gcloud secrets create plane-ai-providers --project my-plane-project --replication-policy user-managed \
      --locations us-central1 --data-file=-
  ```

```hcl
enable_components = { pi = true }
plane_ai          = { providers_secret = "projects/my-plane-project/secrets/plane-ai-providers" }
```

**Embedding model:** `plane_ai.embedding_model` is one of the 1536-dimension models (`cohere/embed-v4.0`,
`openai/text-embedding-3-small`, `openai/text-embedding-ada-002`), because Plane's page search index uses the same
dimension. pi's migrator, which runs at every install and upgrade, sets up the model in OpenSearch from the matching
key. Without that key, Plane AI falls back to BM25 keyword search (no semantic search); after adding the key, the
model is set up at the next upgrade.

**Egress:** the pi pods call the LLM providers' APIs, and the OpenSearch pod calls the embedding provider's API, over
the internet through the module's Cloud NAT. If you restrict egress, allow HTTPS to the providers you use (for example
`api.cohere.ai`, `api.openai.com`, `api.anthropic.com`).

**Rotating keys:** add a new version of the secret. It's picked up within an hour, and Reloader restarts the pi
workloads.

## After install

Open `https://<domain>`, finish the setup wizard, then activate your Plane licence key. SMTP, SSO and AI provider
keys are configured in the admin UI (`/god-mode`) in this release; Plane AI (pi) reads its keys from
`plane_ai.providers_secret` instead.

## Things to know

- **New installs only in this release.** The module generates new app keys (`SECRET_KEY`, `AES_SECRET_KEY`, `AES_SALT`)
  and a new licence identity, and has no inputs for an existing database, bucket or keys.
- **Never change `domain`.** Plane's licence is bound to it. The release and namespace are fixed to `plane`.
- **App keys are generated once and never rotated** (`<name>-plane-app-keys`). Changing them makes stored encrypted
  data unreadable.
- **Plane AI (pi) needs a recent Plane and chart:** the first Plane release whose Plane AI supports GCS storage, and
  plane-enterprise 3.11.7+. The module refuses `enable_components.pi = true` with an older `plane_version`.
- **Redis uses TLS** (`redis.transit_encryption`, on by default): Memorystore's server CA is passed to every Plane service
  through the chart's `customCA` (plane-enterprise 3.11.6+). `false` keeps AUTH over the private network without TLS.
- **Nodes:** 3 zones × 1 `n2d-standard-4`, scaled by the GKE cluster autoscaler up to 2 per zone
  (`node_pool.min_per_zone` / `max_per_zone`). The third node, compared with AWS, carries the in-cluster OpenSearch and
  RabbitMQ.
- **Scaling Plane:** api, worker, web and live run 2 replicas. For more capacity, raise replicas through `plane_values`,
  e.g. `services: { api: { replicas: 4 }, worker: { replicas: 4 } }`.
- **Destroying:** Cloud SQL deletion protection is on. Set `postgres = { deletion_protection = false }` (and
  `bucket_force_destroy = true` unless the bucket is empty, old object versions included), apply, then destroy.
- **After a destroy:** the persistent disks of the in-cluster RabbitMQ and OpenSearch outlive the cluster (Kubernetes
  doesn't delete them with the Helm release): find them with `gcloud compute disks list --filter="name~^pvc-"` and
  delete them. The Cloud SQL instance name has a random suffix, so a reinstall with the same `name` isn't blocked by
  Cloud SQL's week-long name reservation. The project APIs stay on.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.10 |
| google | >= 7.10 |
| helm | >= 3.0 |
| random | >= 3.6 |
| time | >= 0.9 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| addons | ./modules/addons | n/a |
| cluster | ./modules/cluster | n/a |
| data | ./modules/data | n/a |
| edge | ./modules/edge | n/a |
| network | ./modules/network | n/a |
| plane | ./modules/plane | n/a |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| domain | FQDN Plane is served on. It is also the licence domain and part of the instance identity, so it must never change after install. | `string` | n/a | yes |
| name | Prefix for every resource the module creates. Lowercase letters, digits and hyphens, at most 20 characters. | `string` | n/a | yes |
| project\_id | GCP project to deploy into (billing linked). Give Plane a project of its own: GKE admin roles are project-wide. | `string` | n/a | yes |
| region | GCP region for every regional resource (GKE, Cloud SQL, Memorystore, the bucket, the static IPs and the secrets' replicas). | `string` | n/a | yes |
| acme\_email | Path A (ingress.mode = "automated"), variant A.1: the Let's Encrypt account email. cert-manager issues the web<br/>certificate with HTTP-01 through Traefik: Plane must be public on port 80, and the certificate is issued once your<br/>DNS record for domain points at load\_balancer\_ip. Leave null for your own certificates<br/>(ingress.tls\_certificate\_secret, variant A.2) or for path B. | `string` | `null` | no |
| acme\_server | ACME directory URL. Use the Let's Encrypt staging URL for tests to avoid rate limits. | `string` | `"https://acme-v02.api.letsencrypt.org/directory"` | no |
| bucket\_force\_destroy | Allow terraform destroy to delete the uploads bucket even when it holds objects. | `bool` | `false` | no |
| chart\_name | Chart name in chart\_repository (preview builds are named <commit>-plane-enterprise). | `string` | `"plane-enterprise"` | no |
| chart\_repository | Helm repository of the plane-enterprise chart. Override only to test a preview build. | `string` | `"https://helm.plane.so/"` | no |
| chart\_version | plane-enterprise Helm chart version. 3.11.7 or later (from 3.11.6 the bundled RabbitMQ reads its credentials from an External Secrets Secret; 3.11.7 sets the OpenSearch heap Plane AI needs). | `string` | `"3.11.7"` | no |
| cluster\_admin\_members | IAM members (user:…, group:…, serviceAccount:…) granted roles/container.admin on the project. The identity running Terraform needs it already. | `list(string)` | `[]` | no |
| deployment\_mode | How Plane runs. Only "gke" is available in this release. | `string` | `"gke"` | no |
| email | Plane's email service (inbound email to work items). On by default with its own internet-facing passthrough load<br/>balancer on a reserved static IP (ports 25 SMTP, 465 SMTPS, 587 submission), the sender's IP preserved. smtp\_domain is<br/>the domain that receives mail (default "intake.<domain>"): create an A record for it pointing at the<br/>email\_load\_balancer\_ip output and an MX record naming it (see dns\_records). Certificate: your own via<br/>certificate\_secret (a Secret Manager secret like ingress.tls\_certificate\_secret), else the email app's own<br/>self-signed certificate (fine for receiving mail). load\_balancer = false keeps the service running with no load<br/>balancer (not reachable from the internet); enabled = false turns the service and its load balancer off. | <pre>object({<br/>    enabled            = optional(bool, true)<br/>    smtp_domain        = optional(string)<br/>    load_balancer      = optional(bool, true)<br/>    certificate_secret = optional(string)<br/>  })</pre> | `{}` | no |
| enable\_apis | Enable the project APIs the module needs (Compute, GKE, Service Networking, Cloud SQL Admin, Memorystore, Secret Manager, IAM, Cloud Storage). They are left on at destroy. Set false when your organisation enables APIs centrally. | `bool` | `true` | no |
| enable\_components | Optional Plane workloads. pi (Plane AI) needs plane\_ai.providers\_secret, opensearch.enabled and a plane\_version with GCS support in Plane AI. | <pre>object({<br/>    silo   = optional(bool, true)<br/>    drawio = optional(bool, true)<br/>    pi     = optional(bool, false)<br/>  })</pre> | `{}` | no |
| helm\_timeout | Seconds to wait for the Plane Helm release. A fresh install's migrations take about 20 minutes. | `number` | `3600` | no |
| ingress | How traffic reaches Plane. mode = "automated" (path A): the module installs Traefik behind a GCP passthrough<br/>network load balancer on a reserved static IP, Plane's routes and the certificates (Let's Encrypt via acme\_email, or<br/>your own via tls\_certificate\_secret). mode = "none" (path B, default): the module installs no ingress controller or<br/>routes; you bring your controller, routes, certificate and DNS after the apply. The module configures no DNS: the<br/>records are yours in both paths (see the dns\_records output). Path A only: allowed\_cidrs (who can reach Plane),<br/>scheme (internet-facing, or internal: an internal load balancer on an IP in the module's subnet) and<br/>tls\_certificate\_secret (a Secret Manager secret in project\_id, as "projects/<project\_id>/secrets/<name>", whose<br/>value is JSON with the keys "tls.crt" (full chain) and "tls.key"). | <pre>object({<br/>    mode                   = optional(string, "none")<br/>    allowed_cidrs          = optional(list(string), ["0.0.0.0/0"])<br/>    scheme                 = optional(string, "internet-facing")<br/>    tls_certificate_secret = optional(string)<br/>  })</pre> | `{}` | no |
| labels | Labels applied to every GCP resource that supports them (GCP label rules: lowercase keys and values, digits, hyphens and underscores). | `map(string)` | `{}` | no |
| master\_authorized\_networks | CIDRs allowed to reach the GKE API's public endpoint. Default open, as on AWS; restrict this to your office, VPN or CI ranges (Terraform needs it during the apply). | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| network | Address ranges of the VPC the module creates: subnet\_cidr (nodes and internal load balancers), pods\_cidr and<br/>services\_cidr (the subnet's secondary ranges for GKE) and private\_service\_cidr (private services access, for Cloud<br/>SQL and Memorystore). They must not overlap each other or networks you will peer or VPN with. The defaults all sit<br/>in 10.60.0.0/15 and avoid 10.0.0.0/16. | <pre>object({<br/>    subnet_cidr          = optional(string, "10.60.0.0/20")<br/>    services_cidr        = optional(string, "10.60.16.0/20")<br/>    private_service_cidr = optional(string, "10.60.32.0/20")<br/>    pods_cidr            = optional(string, "10.61.0.0/16")<br/>  })</pre> | `{}` | no |
| node\_pool | The GKE node pool, in every zone of the cluster (3 by default): min\_per\_zone to max\_per\_zone nodes per zone, scaled<br/>by the GKE cluster autoscaler (1-2 per zone, so 3-6 nodes). The third node, compared with AWS, carries the in-cluster<br/>OpenSearch and RabbitMQ. spot = true uses Spot VMs (cheaper, can be reclaimed: tests only). | <pre>object({<br/>    machine_type = optional(string, "n2d-standard-4")<br/>    min_per_zone = optional(number, 1)<br/>    max_per_zone = optional(number, 2)<br/>    disk_size_gb = optional(number, 50)<br/>    disk_type    = optional(string, "pd-balanced")<br/>    spot         = optional(bool, false)<br/>  })</pre> | `{}` | no |
| opensearch | OpenSearch for Plane's search, run in the cluster by the chart (GCP has no managed OpenSearch), on by default as in<br/>today's deployments: one node on a persistent disk of volume\_size\_gb, credentials generated, stored in Secret<br/>Manager and synced by External Secrets. The chart's Job creates the search indexes after every install and upgrade.<br/>enabled = false: Plane runs with search indexing off. | <pre>object({<br/>    enabled        = optional(bool, true)<br/>    volume_size_gb = optional(number, 20)<br/>    # Index names are "<index_prefix>_<name>", as today's deployments ("plane"). Changing it on a running install<br/>    # needs the indexes created again and re-filled (manage_search_index index create + document index).<br/>    index_prefix = optional(string, "plane")<br/>  })</pre> | `{}` | no |
| plane\_ai | Plane AI (enable\_components.pi). providers\_secret: a Secret Manager secret in project\_id, as<br/>"projects/<project\_id>/secrets/<name>", that you create before the apply; its value is JSON with the provider API<br/>keys: COHERE\_API\_KEY or OPENAI\_API\_KEY (embeddings, matching embedding\_model), OPENAI\_API\_KEY and/or CLAUDE\_API\_KEY<br/>(the LLM), optionally GROQ\_API\_KEY. The keys never pass through Terraform. embedding\_model: cohere/embed-v4.0,<br/>openai/text-embedding-3-small or openai/text-embedding-ada-002 (1536 dimensions, shared with Plane's search index). | <pre>object({<br/>    providers_secret = optional(string)<br/>    embedding_model  = optional(string, "cohere/embed-v4.0")<br/>  })</pre> | `{}` | no |
| plane\_values | Extra plane-enterprise chart values (YAML string), merged last. Never put secrets here: they end up in Terraform state and the Helm release. | `string` | `""` | no |
| plane\_version | Plane release to install (chart planeVersion). Plane AI (enable\_components.pi) needs the first release whose pi supports GCS storage; the module checks it. | `string` | `"v4.0.1"` | no |
| postgres | Cloud SQL for PostgreSQL: private IP only, TLS required (ENCRYPTED\_ONLY), regional high availability, backups with<br/>point-in-time recovery. The module creates the databases plane and plane\_pi and the user plane (password generated,<br/>in Secret Manager). deletion\_protection turns on both Terraform's and Cloud SQL's own protection. | <pre>object({<br/>    database_version       = optional(string, "POSTGRES_15")<br/>    tier                   = optional(string, "db-custom-2-8192")<br/>    edition                = optional(string, "ENTERPRISE")<br/>    availability_type      = optional(string, "REGIONAL")<br/>    disk_size_gb           = optional(number, 100)<br/>    disk_type              = optional(string, "PD_SSD")<br/>    backup_retention_days  = optional(number, 14)<br/>    point_in_time_recovery = optional(bool, true)<br/>    deletion_protection    = optional(bool, true)<br/>  })</pre> | `{}` | no |
| rabbitmq | RabbitMQ, run in the cluster by the chart (GCP has no managed RabbitMQ): one node on a persistent disk of volume\_size\_gb. Its credentials are generated, stored in Secret Manager and synced by External Secrets. | <pre>object({<br/>    volume_size_gb = optional(number, 10)<br/>  })</pre> | `{}` | no |
| redis | Memorystore for Redis, reached over private services access with an AUTH string (in Secret Manager). STANDARD\_HA<br/>keeps a replica in another zone with automatic failover. transit\_encryption (default true) turns on TLS (port 6378)<br/>with Memorystore's server CA trusted through the chart's customCA (every Plane service, plane-enterprise 3.11.6+);<br/>false keeps AUTH over the private network without TLS. | <pre>object({<br/>    version            = optional(string, "REDIS_7_2")<br/>    tier               = optional(string, "STANDARD_HA")<br/>    memory_size_gb     = optional(number, 4)<br/>    transit_encryption = optional(bool, true)<br/>  })</pre> | `{}` | no |
| release\_channel | GKE release channel. GKE picks and upgrades the Kubernetes version within it. | `string` | `"REGULAR"` | no |
| tls\_secret\_name | Path A: name of the Kubernetes TLS Secret in the plane namespace that Traefik serves. Written by cert-manager (acme\_email) or by External Secrets from ingress.tls\_certificate\_secret. | `string` | `"plane-tls"` | no |
| use\_storage\_proxy | false (default): browsers upload and download directly from the bucket with signed URLs (the bucket allows CORS from domain). true: uploads and downloads go through Plane's api (no CORS needed, bounded by the ingress body limit). | `bool` | `false` | no |
| zones | Zones of region for the GKE nodes. Empty (default): GKE picks three zones of the region. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cloudsql\_instance\_name | Cloud SQL instance name. |
| cloudsql\_private\_ip | Cloud SQL private IP. |
| cluster\_certificate\_authority\_data | GKE cluster CA (base64). |
| cluster\_endpoint | GKE API endpoint (https URL of the public endpoint). |
| cluster\_name | GKE cluster name. |
| configure\_kubectl | Command to point kubectl at the cluster (needs gcloud and gke-gcloud-auth-plugin). |
| deployment\_mode | Deployment mode in use. |
| dns\_records | The DNS records to create (the module creates none). web: path A only; in path B, point domain at your own ingress load balancer. An MX record can't point at an IP, so the email service gets an A record (email\_host) and an MX record naming it (email\_mx). |
| email\_load\_balancer\_ip | Reserved static IP of the email load balancer (null without email.load\_balancer). email.smtp\_domain's A record points here, and its MX record names smtp\_domain. |
| gcs\_bucket\_name | Uploads bucket. |
| load\_balancer\_ip | Path A: the reserved static IP of Traefik's load balancer (null in path B). Point domain here with an A record. Internal (an IP in the module's subnet) when ingress.scheme = "internal". |
| network\_name | VPC network name. |
| plane\_helm\_values | The plane-enterprise chart values the module generates from the infrastructure (YAML): endpoints, bucket, project, domain, load balancer and Secret names; no secret values. Excludes plane\_values. For support, debugging and reading what was installed. |
| plane\_service\_account\_email | Google service account Plane's pods use through GKE Workload Identity. |
| plane\_url | URL Plane is served on. |
| rabbitmq\_endpoint | In-cluster RabbitMQ (AMQP) host. |
| redis\_endpoint | Memorystore for Redis endpoint (host:port; port 6378 with TLS, 6379 without). |
| secret\_ids | Secret Manager secrets the deployment uses (IDs only, never values). |
| subnet\_name | Subnet the GKE nodes run in. |
<!-- END_TF_DOCS -->
