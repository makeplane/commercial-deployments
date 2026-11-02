# terraform-aws-plane

Terraform module that deploys [Plane](https://plane.so) Commercial on AWS with one `terraform apply`, in one of two
modes (`deployment_mode`):

| Mode | What runs | For |
|---|---|---|
| `eks` (default) | The network, an EKS cluster, managed data services (RDS, ElastiCache, Amazon MQ, OpenSearch, S3) and Plane itself (the `plane-enterprise` Helm chart) | Production, multi-AZ |
| `docker` | One EC2 instance running Plane's Docker Compose stack with the bundled Postgres, Valkey, RabbitMQ and MinIO, data on an encrypted EBS volume, backups to S3 | Small teams, trials; see [Docker mode](#docker-mode) |

The sections up to "Things to know" describe EKS mode.

> **Status:** under development. It will be published to the Terraform Registry as `makeplane/plane/aws` from
> `v0.1.0`; until then, reference it from this repository. It doesn't change or replace the older `aws/terraform`
> module or the `kustomize/` setup.

## What it creates

| Layer | Resources | Defaults |
|---|---|---|
| Network | VPC, 3 private + 3 public subnets, NAT, S3 gateway endpoint, flow logs | Workloads only in private subnets; one shared NAT gateway |
| Cluster | EKS (access entries, secrets encryption, control-plane logs), one managed node group, managed add-ons (vpc-cni, coredns, kube-proxy, Pod Identity agent, EBS CSI) | Kubernetes 1.36, m7a.xlarge, 2 nodes (range 2–4, as today; no autoscaler) |
| PostgreSQL | RDS for PostgreSQL **Multi-AZ DB cluster** (1 writer + 2 readable standbys) | 15.19, `db.m6gd.large`, 100 GB io1 / 1000 IOPS, KMS, TLS required, master password managed by RDS |
| Cache | ElastiCache **Valkey** | 8.2, `cache.t3.medium`, TLS + AUTH token + at-rest encryption |
| Queue | Amazon MQ for RabbitMQ | 3.13, `mq.m7g.medium`, multi-AZ cluster, AMQPS only, private |
| Search | Amazon OpenSearch Service, `opensearch.enabled` | On, as today: 2.19, 2 × `r7g.large.search` across 2 zones, 10 GB gp3, in the VPC, HTTPS only, KMS; Plane signs with its Pod Identity role (no passwords) |
| Email | Plane's email service (inbound email to work items) on its own internet-facing NLB | On by default: ports 25/465/587, sender IP preserved, receiving mail for `intake.<domain>`; you create the MX record |
| Storage | S3 uploads bucket | SSE-KMS, no public access, TLS-only policy, versioning, CORS for your domain |
| Secrets | Secrets Manager (Valkey token, MQ user, app keys) + the RDS-managed master secret | KMS-encrypted; values never pass through Terraform variables |
| Edge | **Path A** (`ingress.mode = "automated"`): Traefik behind an NLB (AWS-assigned IPs), Plane's routes, certificates (Let's Encrypt HTTP-01 or yours from Secrets Manager). **Path B** (default): none; you bring your ingress | The module configures no DNS: you create the records (`dns_records` output) |
| In cluster (Helm) | AWS Load Balancer Controller 2.x, External Secrets, Reloader, metrics-server, **plane-enterprise**; path A also Traefik and (with Let's Encrypt) cert-manager | Pods reach S3 and Secrets Manager through **EKS Pod Identity**: no IAM users, no access keys |
| Plane workloads | web, space, admin, api, worker, beat-worker, live, live-exporter, silo, drawio, plus the services paid features need: outbox-poller, automation-consumer, runner (Automations), agent-consumer, webhook-consumer, iframely (link previews), worker-importers (imports, on their own queue), email | api, worker, web and live run 2 replicas spread across nodes, with PodDisruptionBudgets; the rest 1. Plane AI (pi) off. Any attachment type can be uploaded, as today |

## Usage

```hcl
provider "aws" {
  region = "us-east-1"
}

provider "helm" {
  kubernetes = {
    host                   = module.plane.cluster_endpoint
    cluster_ca_certificate = base64decode(module.plane.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.plane.cluster_name, "--region", "us-east-1"]
    }
  }
}

module "plane" {
  source = "git::https://github.com/makeplane/commercial-deployments.git//aws/terraform-aws-plane?ref=<tag>"

  name       = "plane"
  domain     = "plane.example.com"
  ingress    = { mode = "automated" } # path A; omit for path B (bring your own ingress)
  acme_email = "ops@example.com"      # Let's Encrypt for the web certificate
}
```

A full example is in [`examples/complete`](examples/complete). For a step-by-step installation, see the
[deployment guide](docs/deployment-guide.md).

## Prerequisites

- Terraform ≥ 1.10 (S3 state locking with `use_lockfile`) and the **AWS CLI v2** (Helm authenticates to EKS with `aws eks get-token`).
- Credentials allowed to create VPC and EC2 networking (security groups, launch templates, an Elastic IP), EKS, IAM
  roles and policies, RDS, ElastiCache, Amazon MQ, OpenSearch Service, S3, KMS, Secrets Manager, CloudWatch Logs,
  service-linked roles, and to read Elastic Load Balancing. In practice, an administrator role.
- A region with at least 3 Availability Zones (the RDS Multi-AZ DB cluster needs them).
- The OpenSearch service-linked role, if OpenSearch has never been used in the account (AWS creates it automatically
  only from the console): `aws iam create-service-linked-role --aws-service-name es.amazonaws.com`.
- Network access from where you run Terraform to the EKS API endpoint. It's public by default; restrict it with
  `cluster_endpoint_public_access_cidrs`.
- An **encrypted remote state backend**. State holds generated secrets (Valkey token, MQ password, app keys).
- Service quota for 1 Elastic IP (the NAT gateway). The load balancer's IPs are assigned by AWS.

## Ingress, certificates and DNS

Two paths, chosen with `ingress.mode`. **The module configures no DNS in either**: after the apply, create the records
from the `dns_records` output.

| | Path A: automated (`ingress.mode = "automated"`) | Path B: bring your own (`ingress.mode = "none"`, default) |
|---|---|---|
| Ingress controller | Traefik behind an NLB, installed by the module | Yours (Traefik, NGINX, OpenShift, ALB, …), after the apply |
| Plane's routes | Created by the module | Yours: generate them from the chart (below) |
| Web certificate | **A.1** Let's Encrypt (`acme_email`, HTTP-01), or **A.2** yours from Secrets Manager (`ingress.tls_certificate_secret_arn`) | Yours |
| Email certificate | Yours from Secrets Manager (`email.certificate_secret_arn`), else self-signed | Same |
| DNS | Yours: CNAME `domain` → `load_balancer_dns_name`, MX `smtp_domain` → email NLB | Yours: `domain` → your ingress load balancer, MX `smtp_domain` → email NLB |

**Path A, A.1 (Let's Encrypt):** cert-manager proves domain ownership over HTTP (HTTP-01), so Plane must be reachable
from the internet on port 80 (`ingress.allowed_cidrs` includes `0.0.0.0/0`, internet-facing; the module checks this).
The certificate is issued once your DNS record points at `load_balancer_dns_name`; cert-manager keeps retrying until
then, and Traefik serves its default certificate meanwhile. Renewal is automatic. Use the Let's Encrypt staging server
(`acme_server`) while testing.

**Your own certificates (A.2, and the email certificate):** store each in AWS Secrets Manager before the apply, in
the same account and region, as a JSON secret with the keys `tls.crt` (full chain, PEM) and `tls.key`. Encrypt it with
the default `aws/secretsmanager` key (after the first apply, this module's KMS key also works; other KMS keys don't),
and pass its full ARN. External Secrets copies it into the cluster; pods that mount it wait until it has. To renew,
update the secret value: it's picked up within an hour, Traefik reloads it and the email pod restarts automatically.
The same secret can serve web and email if the certificate lists both names.

```bash
aws secretsmanager create-secret --name plane/web-tls \
  --secret-string "$(jq -n --rawfile crt fullchain.pem --rawfile key privkey.pem '{"tls.crt": $crt, "tls.key": $key}')"
```

**DNS records:** use a CNAME (or an alias record in Route 53), never A records to the load balancers' current IPs, which
AWS assigns and can change. For a zone apex, use your provider's alias/flattening record. Keep Cloudflare records
DNS-only (no proxy): Traefik terminates TLS.

**Path B routes:** generate Plane's routes for your controller from the chart and the values the module generated
(`chart_version`, default 3.11.3; if you set `plane_values`, add it as a second `-f`). The routes serve TLS from the Secret named by `tls_secret_name` (`plane-tls`) in
namespace `plane`, except on OpenShift, where the router terminates TLS (edge).

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

# OpenShift (one Route per path)
helm template plane plane/plane-enterprise --version <chart_version> -n plane -f plane-values.yaml \
  --set ingress.enabled=true,ingress.controller=openshift \
  --show-only templates/ingress-openshift.yaml > plane-routes.yaml

kubectl -n plane apply -f plane-routes.yaml   # regenerate and re-apply after every Plane upgrade
```

Other controllers: use the generated NGINX Ingress as the route table (paths → services and ports). Plane needs
WebSockets on `/live/` and an upload limit of at least 20 MB.

Destroy in path B in reverse: remove your routes, then your ingress controller and its load balancer, then
`terraform destroy` (a leftover load balancer blocks deleting the VPC).

## Search (OpenSearch)

On by default, as in today's deployments: a private Amazon OpenSearch Service domain. Plane reaches it with its Pod
Identity role (SigV4): there are no users or passwords, and the domain policy allows only that role. Set
`opensearch = { enabled = false }` to run without it: Plane then has search indexing off, and search behaves
differently from today's installs.

**Search indexes are created automatically:** after every install and upgrade, the chart's `plane-api-search-index`
Job (plane-enterprise 3.11.3+) waits for the database migrations and creates any missing index. Index names are
`<opensearch.index_prefix>_<name>` (prefix `plane`, as today's deployments). Changing mappings stays manual, when a
Plane release's notes ask for it:

```bash
kubectl -n plane exec deploy/plane-api-wl -- python manage.py manage_search_index list
kubectl -n plane exec deploy/plane-api-wl -- python manage.py manage_search_index index update --force   # added fields
kubectl -n plane exec deploy/plane-api-wl -- python manage.py manage_search_index index rebuild --force  # changed mappings, then:
kubectl -n plane exec deploy/plane-api-wl -- python manage.py manage_search_index document index --force
```

## Email

Plane's email service turns inbound email into work items. It's **on by default with its own internet-facing NLB**,
receiving mail for **`intake.<domain>`** (set `email.smtp_domain` for another domain):

- **Load balancer:** ports 25 SMTP, 465 SMTPS, 587 submission, named `<name>-email`, with instance targets and
  `externalTrafficPolicy: Local`, so the email service sees the sender's real IP (SPF). The hostname is the
  `email_load_balancer_dns_name` output.
- **MX record:** yours: `<smtp_domain> MX 10 <email NLB>` (see `dns_records`). The default is a subdomain so it never
  collides with a CNAME on `domain` (an MX record can't share a name with a CNAME).
- **Certificate** (STARTTLS/SMTPS): yours from Secrets Manager (`email.certificate_secret_arn`, see above); otherwise the
  email service generates a self-signed one at startup. Mail servers delivering on port 25 use opportunistic TLS and
  accept it; mail clients on 465/587 will warn. In path A with the email load balancer on, the module shows a warning
  (not an error) when it's missing.

The email NLB is always internet-facing and open to all senders on its three ports (mail servers anywhere must reach
it). `email = { load_balancer = false }` keeps the service running with no load balancer (not reachable from the
internet, like today's managed deployment); `email = { enabled = false }` turns the service and its load balancer off. The NLB costs about $27/month.
Needs plane-enterprise chart 3.11.3 or later.

## After install

Open `https://<domain>`, finish the setup wizard, then activate your Plane licence key. SMTP, SSO and AI provider
keys are configured in the admin UI (`/god-mode`) in this release.

## Things to know

- **New installs only in this release.** The module generates new app keys (`SECRET_KEY`, `AES_SECRET_KEY`, `AES_SALT`)
  and a new licence identity, and has no inputs for an existing database snapshot, bucket or keys. Moving an existing
  installation's data onto it would leave encrypted fields unreadable and need the licence re-activated.
- **Never change `domain`.** Plane's licence is bound to it. The release and namespace are fixed to `plane`; the chart
  also derives `MACHINE_SIGNATURE` from the licence server, domain, namespace and release, which Plane v4 only uses to
  carry over an older install's licence identity (new installs get a key pair stored in the database).
- **App keys are generated once and never rotated** (`plane/<name>/app-keys`). Changing them makes stored encrypted
  data unreadable.
- **Nodes:** 2 by default, range 2–4 (`node_group.min_size` / `max_size` / `desired_size`). There's no node autoscaler
  yet, and Terraform sets the node count only when it creates the group. Scale by hand with
  `aws eks update-nodegroup-config --cluster-name <name> --nodegroup-name <group> --scaling-config desiredSize=3`
  (`aws eks list-nodegroups --cluster-name <name>` gives the group name); the next apply leaves it alone. Raising `min_size` above the current count makes AWS reject the change.
- **Scaling Plane:** api, worker, web and live run 2 replicas (today's kustomize default was 5 api / 5 worker). For more
  capacity, raise replicas through `plane_values`, e.g. `services: { api: { replicas: 4 }, worker: { replicas: 4 } }`,
  and add nodes to match. There are no autoscalers in this release.
- **Cache:** Valkey is a single node by default (`redis.replicas = 0`), unlike the Multi-AZ database and queue. Set
  `redis = { replicas = 1 }` for automatic failover.
- **Destroying:** RDS deletion protection is on. Set `postgres = { deletion_protection = false }` (and
  `bucket_force_destroy = true` unless the bucket is empty, old object versions included), apply, then destroy.
  Otherwise `terraform destroy` stops with an error.
- **After a destroy:** RDS keeps a final snapshot `<name>-pg-final`, encrypted with the module's KMS key, which is
  deleted 30 days after the destroy: restore or copy the snapshot before then if you need it. Secrets Manager keeps
  the secrets for 7 days. To reinstall with the same `name`, delete the snapshot and force-delete the `plane/<name>/*`
  secrets first.

## Docker mode

`deployment_mode = "docker"` (`examples/docker` is the shortest start). One `terraform apply` creates:

| Resource | Details |
|---|---|
| Network | The same VPC. Path A internet-facing: the instance in a public subnet with an **Elastic IP** and no NAT gateway; otherwise a private subnet behind NAT |
| Instance | Ubuntu 24.04 (x86_64) from Canonical's SSM parameter, `docker.instance_type` (`m7a.xlarge`; burstable types rejected), IMDSv2 with hop limit 1, **no key pair, no port 22, no user data**; shell through SSM Session Manager (`ssm_session_command`) |
| Data | Encrypted gp3 **data volume** (`docker.data_volume_gb`, 100 GB) at `/opt/plane`, separate from the instance; final snapshot on destroy |
| Secrets | `plane/<name>/app-keys` (Plane's keys, `MACHINE_SIGNATURE`) and `plane/<name>/bundled-services` (Postgres, RabbitMQ, MinIO), generated once, KMS-encrypted |
| Setup | An SSM document with the setup scripts; its association installs Docker Engine and Compose (pinned: `docker.docker_version`, `docker.compose_version`), fetches the release's `docker-compose.yml` and `variables.env`, writes `/opt/plane/plane.env` (0600) with the generated secrets, runs `docker compose pull` and `up -d` and waits for migrations and health. **The apply waits for it and fails if it fails** |
| Backups | Daily EBS snapshots (Data Lifecycle Manager) and a nightly `pg_dump` + MinIO mirror to a KMS-encrypted, versioned S3 bucket (`backup_bucket_name`), kept `docker.backup_retention_days` |

**Edge.** Path A (the Docker default): Plane's own Caddy proxy terminates TLS on the instance, with Let's Encrypt
(`acme_email`, HTTP-01: port 80 open to the internet) or your certificate from Secrets Manager
(`ingress.tls_certificate_secret_arn`, same format as EKS; copied daily). `ingress.scheme = "internal"` keeps the
instance private (your certificate only). Path B (`ingress = { mode = "none" }`): a private instance serving plain HTTP
on port 80 to your own load balancer (ALB with ACM, WAF, …) in the VPC. DNS is yours: `dns_records` gives an **A**
record to the Elastic IP (or the private IP when internal) and, with email, `intake.<domain> MX 10 <domain>`.
`email.load_balancer` means "open 25/465/587 on the instance" in this mode.

**Release files (`docker.compose_assets_url`).** The setup downloads `<url>/<plane_version>/docker-compose.yml` and
`variables.env` (`https://` or `s3://`; the instance role may read an `s3://` prefix). The default is Plane's public
asset URL; until Plane publishes a release there, the setup stops with "returned HTML": host the two files yourself
(S3 in the same region is simplest) and pin them with `docker.compose_assets_sha256`. The module doesn't ship Plane's
files.

**plane.env.** Plane's `variables.env` for the release, with the module's settings (`plane_env` output) and the
generated secrets replacing the shipped values in place: `SECRET_KEY`, the AES, HMAC, live, pi, webhook and Argus
keys, the Postgres password together with `DATABASE_URL`/`PLANE_PI_DATABASE_URL`/`FOLLOWER_POSTGRES_URI`, the
RabbitMQ password with `AMQP_URL`, and the MinIO keys (MinIO is reachable through `/uploads`, so shared defaults would
be a real exposure). The setup refuses to start Plane if any of them is empty or still at Plane's default. Add
settings with `docker.extra_env` (not secrets: it's stored in the SSM document). `AES_SALT` is left alone on purpose:
the Compose stack doesn't pass it, and setting it later would make stored data unreadable.

**Day 2.** Upgrade by raising `plane_version` (a database dump to S3 first; migrations run in the `migrator`
service; downgrades are refused). Settings changes re-run the setup. Replace a broken instance with
`terraform apply -replace='module.<name>.module.docker[0].aws_instance.this'`: the data volume and Elastic IP move
over. Restore: `docker.data_volume_snapshot_id` plus an instance replacement, or the S3 dumps. Runbooks:
[deployment guide, section 13](docs/deployment-guide.md#13-docker-mode).

**Outbound access** the instance needs: Docker Hub (images), `download.docker.com`, Ubuntu mirrors and
`snapcraft.io` (AWS CLI), the asset URL, `prime.plane.so` (licence registration, at every API start), Let's Encrypt
(A.1), AWS APIs (SSM, Secrets Manager, S3).

**Limits.** One instance in one AZ (recovery = replacement or restore), no search indexing (no OpenSearch service in
the stack), no draw.io, x86_64 only. Destroying: set `bucket_force_destroy = true` if the backups bucket has
objects; the volume's final and daily snapshots are encrypted with the module's KMS key, deleted 30 days after the
destroy.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.10 |
| aws | >= 6.28 |
| helm | >= 3.0 |
| random | >= 3.6 |
| time | >= 0.9 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 6.28 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| addons | ./modules/addons | n/a |
| cluster | ./modules/cluster | n/a |
| data | ./modules/data | n/a |
| docker | ./modules/docker | n/a |
| edge | ./modules/edge | n/a |
| network | ./modules/network | n/a |
| plane | ./modules/plane | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| domain | FQDN Plane is served on. It is also the licence domain and part of the instance identity, so it must never change after install. | `string` | n/a | yes |
| name | Prefix for every resource the module creates. Lowercase letters, digits and hyphens, at most 20 characters. | `string` | n/a | yes |
| acme\_email | Path A (ingress.mode = "automated"), variant A.1: the Let's Encrypt account email. The web certificate is issued<br/>with HTTP-01 (EKS: cert-manager through Traefik; Docker: the stack's Caddy proxy): Plane must be public on port 80,<br/>and the certificate is issued once your DNS record for domain points at Plane (dns\_records). Leave null for your<br/>own certificates (ingress.tls\_certificate\_secret\_arn, variant A.2) or for path B. | `string` | `null` | no |
| acme\_server | ACME directory URL. Use the Let's Encrypt staging URL for tests to avoid rate limits. | `string` | `"https://acme-v02.api.letsencrypt.org/directory"` | no |
| addon\_versions | EKS mode: EKS managed add-on versions. null for an add-on means the most recent version for kubernetes\_version. | <pre>object({<br/>    vpc_cni                = optional(string, "v1.23.2-eksbuild.8")<br/>    coredns                = optional(string, "v1.14.7-eksbuild.22")<br/>    kube_proxy             = optional(string, "v1.36.0-eksbuild.58")<br/>    eks_pod_identity_agent = optional(string, "v1.4.1-eksbuild.3")<br/>    aws_ebs_csi_driver     = optional(string, "v1.67.2-eksbuild.1")<br/>  })</pre> | `{}` | no |
| az\_count | Availability zones to use. The RDS Multi-AZ DB cluster needs at least 3. Docker mode uses the first one for the instance. | `number` | `3` | no |
| bucket\_force\_destroy | Allow terraform destroy to delete the uploads bucket (EKS) or the backups bucket (Docker) even when it holds objects. | `bool` | `false` | no |
| chart\_name | EKS mode: chart name in chart\_repository (preview builds are named <commit>-plane-enterprise). | `string` | `"plane-enterprise"` | no |
| chart\_repository | EKS mode: Helm repository of the plane-enterprise chart. Override only to test a preview build. | `string` | `"https://helm.plane.so/"` | no |
| chart\_version | EKS mode: plane-enterprise Helm chart version. 3.11.3 or later (configurable email Service). | `string` | `"3.11.3"` | no |
| cluster\_admin\_principal\_arns | EKS mode: IAM principal ARNs granted cluster-admin through EKS access entries. The identity running Terraform is added automatically. | `list(string)` | `[]` | no |
| cluster\_endpoint\_public\_access\_cidrs | EKS mode: CIDRs allowed to reach the public EKS API endpoint. The private endpoint is always on. Restrict this to your office, VPN or CI ranges. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| deployment\_mode | How Plane runs. "eks": EKS with managed data services (RDS, ElastiCache, Amazon MQ, OpenSearch, S3). "docker": one<br/>EC2 instance running Plane's Docker Compose stack with the bundled data services (see the docker input). Never<br/>change it on an existing installation: switching modes is a migration. | `string` | `"eks"` | no |
| docker | Docker mode (deployment\_mode = "docker"): one EC2 instance (Ubuntu 24.04, x86\_64) runs Plane's published Docker<br/>Compose stack with the bundled Postgres, Valkey, RabbitMQ and MinIO; data on a separate encrypted EBS volume<br/>(data\_volume\_gb, mounted at /opt/plane). SSM installs Docker (docker\_version, compose\_version: a version or prefix<br/>in Docker's apt repository), fetches <compose\_assets\_url>/<plane\_version>/docker-compose.yml and variables.env<br/>(https:// or s3://; compose\_assets\_sha256 = { "docker-compose.yml" = "<sha256>", "variables.env" = "<sha256>" }<br/>to pin them), writes plane.env with the generated secrets and starts the stack; the apply waits up to<br/>setup\_timeout\_minutes. extra\_env: more plane.env settings (no secrets: they're stored in the SSM document; not the<br/>keys the module sets). Backups: daily EBS snapshots and a nightly pg\_dump + MinIO mirror to S3 at backup\_time<br/>(UTC, HH:MM), kept backup\_retention\_days. data\_volume\_snapshot\_id restores the data volume from a snapshot.<br/>Ignored in EKS mode. | <pre>object({<br/>    instance_type           = optional(string, "m7a.xlarge")<br/>    data_services           = optional(string, "bundled")<br/>    root_volume_gb          = optional(number, 50)<br/>    data_volume_gb          = optional(number, 100)<br/>    data_volume_snapshot_id = optional(string)<br/>    compose_assets_url      = optional(string, "https://prime.plane.so/deployment/assets")<br/>    compose_assets_sha256   = optional(map(string), {})<br/>    docker_version          = optional(string, "29.9.2")<br/>    compose_version         = optional(string, "5.6.1")<br/>    extra_env               = optional(map(string), {})<br/>    backup_time             = optional(string, "03:00")<br/>    backup_retention_days   = optional(number, 14)<br/>    setup_timeout_minutes   = optional(number, 60)<br/>  })</pre> | `{}` | no |
| email | Plane's email service (inbound email to work items). On by default with its own internet-facing NLB (ports 25 SMTP,<br/>465 SMTPS, 587 submission), the sender's IP preserved. smtp\_domain is the domain that receives mail (default<br/>"intake.<domain>"): create its MX record pointing at the email\_load\_balancer\_dns\_name output (see dns\_records).<br/>Docker mode has no load balancer: load\_balancer = true opens the three ports on the instance (path A<br/>internet-facing: to everyone, MX record pointing at domain; otherwise only from where Plane is reachable).<br/>Certificate: your own via certificate\_secret\_arn (a Secrets Manager secret like ingress.tls\_certificate\_secret\_arn),<br/>else the email app's own self-signed certificate (fine for receiving mail). load\_balancer = false keeps the<br/>service running with no load balancer (not reachable from the internet); enabled = false turns the service and<br/>its load balancer off. Needs plane-enterprise chart 3.11.3+. | <pre>object({<br/>    enabled                = optional(bool, true)<br/>    smtp_domain            = optional(string)<br/>    load_balancer          = optional(bool, true)<br/>    certificate_secret_arn = optional(string)<br/>  })</pre> | `{}` | no |
| enable\_components | Optional Plane workloads. pi (Plane AI) needs AI provider keys, which are set in the admin UI in this release. drawio is EKS only (the Compose stack has no drawio service). | <pre>object({<br/>    silo   = optional(bool, true)<br/>    drawio = optional(bool, true)<br/>    pi     = optional(bool, false)<br/>  })</pre> | `{}` | no |
| helm\_timeout | EKS mode: seconds to wait for the Plane Helm release. A fresh install's migrations take about 20 minutes. | `number` | `3600` | no |
| ingress | How traffic reaches Plane. mode = "automated" (path A): EKS installs Traefik behind an NLB, Plane's routes and the<br/>certificates; Docker serves Plane from the stack's Caddy proxy on the instance (an Elastic IP when internet-facing).<br/>Certificates: Let's Encrypt via acme\_email, or your own via tls\_certificate\_secret\_arn. mode = "none" (path B):<br/>EKS installs no ingress controller or routes; Docker puts the instance in a private subnet serving plain HTTP on<br/>port 80 for your own load balancer. Default: "none" in EKS mode, "automated" in Docker mode. The module configures<br/>no DNS: the records are yours in both paths (see the dns\_records output). Path A only: allowed\_cidrs (who can<br/>reach Plane), scheme (internet-facing or internal) and tls\_certificate\_secret\_arn (a Secrets Manager secret with<br/>JSON keys "tls.crt" and "tls.key", full chain, encrypted with the default aws/secretsmanager key or this module's<br/>KMS key). | <pre>object({<br/>    mode                       = optional(string)<br/>    allowed_cidrs              = optional(list(string), ["0.0.0.0/0"])<br/>    scheme                     = optional(string, "internet-facing")<br/>    tls_certificate_secret_arn = optional(string)<br/>  })</pre> | `{}` | no |
| kubernetes\_version | EKS mode: EKS Kubernetes version. | `string` | `"1.36"` | no |
| node\_group | EKS mode: the managed node group: starts at desired\_size nodes and can range from min\_size to max\_size (2 to 4 by default, as<br/>today). No node autoscaler in this release, so it stays at desired\_size until scaled by hand (aws eks<br/>update-nodegroup-config --scaling-config desiredSize=N) or by an autoscaler added later. Terraform sets desired\_size<br/>only at creation and leaves later changes alone. | <pre>object({<br/>    instance_types = optional(list(string), ["m7a.xlarge"])<br/>    min_size       = optional(number, 2)<br/>    max_size       = optional(number, 4)<br/>    desired_size   = optional(number, 2)<br/>    disk_size_gb   = optional(number, 50)<br/>  })</pre> | `{}` | no |
| opensearch | EKS mode: Amazon OpenSearch Service for Plane's search, on by default as in today's deployments: a private domain in the VPC<br/>(HTTPS only, KMS, node-to-node encryption), reached by Plane with its Pod Identity role (SigV4, no passwords). The<br/>chart's Job creates the search indexes after every install and upgrade. enabled = false: Plane runs with search<br/>indexing off. Docker mode has no search service (search indexing off). | <pre>object({<br/>    enabled        = optional(bool, true)<br/>    engine_version = optional(string, "OpenSearch_2.19")<br/>    instance_type  = optional(string, "r7g.large.search")<br/>    instance_count = optional(number, 2)<br/>    volume_size_gb = optional(number, 10)<br/>    # Index names are "<index_prefix>_<name>", as today's deployments ("plane"). Changing it on a running install<br/>    # needs the indexes created again and re-filled (manage_search_index index create + document index).<br/>    index_prefix = optional(string, "plane")<br/>  })</pre> | `{}` | no |
| plane\_values | EKS mode: extra plane-enterprise chart values (YAML string), merged last. Never put secrets here: they end up in Terraform state and the Helm release. | `string` | `""` | no |
| plane\_version | Plane release to install (EKS: the chart's planeVersion; Docker: the compose assets and image tag). Upgrade by raising it; downgrades aren't supported. | `string` | `"v4.0.1"` | no |
| postgres | EKS mode: RDS PostgreSQL Multi-AZ DB cluster (1 writer + 2 readable standbys), sized as today's module. | <pre>object({<br/>    engine_version        = optional(string, "15.19")<br/>    instance_class        = optional(string, "db.m6gd.large")<br/>    allocated_storage_gb  = optional(number, 100)<br/>    storage_type          = optional(string, "io1")<br/>    iops                  = optional(number, 1000)<br/>    backup_retention_days = optional(number, 14)<br/>    deletion_protection   = optional(bool, true)<br/>  })</pre> | `{}` | no |
| rabbitmq | EKS mode: Amazon MQ for RabbitMQ. | <pre>object({<br/>    engine_version  = optional(string, "3.13")<br/>    instance_type   = optional(string, "mq.m7g.medium")<br/>    deployment_mode = optional(string, "CLUSTER_MULTI_AZ")<br/>  })</pre> | `{}` | no |
| redis | EKS mode: ElastiCache Valkey with TLS, an AUTH token and at-rest encryption, as Plane's own production cache. | <pre>object({<br/>    engine_version = optional(string, "8.2")<br/>    node_type      = optional(string, "cache.t3.medium")<br/>    replicas       = optional(number, 0)<br/>  })</pre> | `{}` | no |
| single\_nat\_gateway | One shared NAT gateway (cheaper, as today's module) instead of one per AZ. Docker mode, path A internet-facing, has no NAT gateway (the instance uses its Elastic IP). | `bool` | `true` | no |
| tags | Tags applied to every AWS resource. | `map(string)` | `{}` | no |
| tls\_secret\_name | EKS mode, path A: name of the Kubernetes TLS Secret in the plane namespace that Traefik serves. Written by cert-manager (acme\_email) or by External Secrets from ingress.tls\_certificate\_secret\_arn. | `string` | `"plane-tls"` | no |
| vpc\_cidr | CIDR of the VPC the module creates. Must not overlap networks you will peer or VPN with. The default avoids 10.0.0.0/16, the default of most VPC tooling and of the older aws/terraform module. | `string` | `"10.60.0.0/16"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| backup\_bucket\_name | Docker mode: S3 bucket with the nightly database dumps, the MinIO mirror and the SSM command output. |
| cluster\_certificate\_authority\_data | EKS cluster CA (base64; null in Docker mode). |
| cluster\_endpoint | EKS API endpoint (null in Docker mode). |
| cluster\_name | EKS cluster name (null in Docker mode). |
| configure\_kubectl | Command to point kubectl at the cluster (null in Docker mode). |
| data\_volume\_id | Docker mode: EBS data volume mounted at /opt/plane. |
| deployment\_mode | Deployment mode in use. |
| dns\_records | The DNS records to create (the module creates none). web: EKS path A (CNAME to the NLB) or Docker path A (A record to the Elastic IP, or to the private IP when internal); null in path B, where domain points at your own load balancer. email\_mx: the MX record for email.smtp\_domain. |
| email\_load\_balancer\_dns\_name | EKS: hostname of the email NLB (null without email.load\_balancer, and in Docker mode). email.smtp\_domain's MX record points here. |
| instance\_id | Docker mode: EC2 instance ID. |
| instance\_private\_ip | Docker mode: private IP of the instance (path B: your load balancer's target, port 80). |
| instance\_public\_ip | Docker mode: the Elastic IP (path A internet-facing; null otherwise). It survives instance replacement. |
| instance\_security\_group\_id | Docker mode: security group of the instance. |
| kms\_key\_arn | KMS key encrypting the data: RDS, ElastiCache, S3 and the secrets (EKS); the volumes, secrets and backups (Docker). |
| load\_balancer\_dns\_name | EKS path A: hostname of the Traefik NLB (null in path B and in Docker mode). Point domain here with a CNAME (or an alias record in Route 53), never A records to its current IPs: AWS assigns them and they can change. |
| plane\_env | Docker mode: the plane.env settings the module manages, without the secrets (those come from Secrets Manager on the instance). The rest of plane.env is Plane's variables.env for plane\_version. |
| plane\_helm\_values | The plane-enterprise chart values the module generates from the infrastructure (YAML): endpoints, bucket, region, domain, load balancer and Secret names; no secret values. Excludes plane\_values. For support, debugging and reading what was installed. Null in Docker mode (see plane\_env). |
| plane\_iam\_role\_arn | IAM role Plane's pods use through EKS Pod Identity (null in Docker mode). |
| plane\_url | URL Plane is served on. |
| private\_subnet\_ids | Private subnet IDs. |
| rabbitmq\_endpoint | Amazon MQ AMQPS host (EKS mode). |
| rds\_endpoint | RDS cluster writer endpoint (EKS mode). |
| redis\_endpoint | ElastiCache primary endpoint (TLS; EKS mode). |
| rerun\_setup\_command | Docker mode: run the converge (setup, upgrade, repair) again without a Terraform change. |
| s3\_bucket\_name | Uploads bucket (EKS mode; Docker mode stores uploads in the bundled MinIO). |
| secret\_arns | Secrets Manager ARNs the deployment uses (ARNs only, never values). |
| ssm\_output\_s3\_uri | Docker mode: where the setup, backup and certificate jobs write their output (one folder per run). |
| ssm\_session\_command | Docker mode: shell on the instance through SSM Session Manager (no SSH). Needs the Session Manager plugin for the AWS CLI. |
| vpc\_id | VPC ID. |
<!-- END_TF_DOCS -->
