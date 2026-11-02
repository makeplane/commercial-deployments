# terraform-aws-plane

Terraform module that deploys [Plane](https://plane.so) Commercial on AWS with one `terraform apply`: the network,
an EKS cluster, managed data services and Plane itself (the `plane-enterprise` Helm chart).

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
| acme\_email | Path A (ingress.mode = "automated"), variant A.1: the Let's Encrypt account email. cert-manager issues the web<br/>certificate with HTTP-01 through Traefik: Plane must be public on port 80, and the certificate is issued once your<br/>DNS record for domain points at load\_balancer\_dns\_name. Leave null for your own certificates<br/>(ingress.tls\_certificate\_secret\_arn, variant A.2) or for path B. | `string` | `null` | no |
| acme\_server | ACME directory URL. Use the Let's Encrypt staging URL for tests to avoid rate limits. | `string` | `"https://acme-v02.api.letsencrypt.org/directory"` | no |
| addon\_versions | EKS managed add-on versions. null for an add-on means the most recent version for kubernetes\_version. | <pre>object({<br/>    vpc_cni                = optional(string, "v1.23.2-eksbuild.8")<br/>    coredns                = optional(string, "v1.14.7-eksbuild.22")<br/>    kube_proxy             = optional(string, "v1.36.0-eksbuild.58")<br/>    eks_pod_identity_agent = optional(string, "v1.4.1-eksbuild.3")<br/>    aws_ebs_csi_driver     = optional(string, "v1.67.2-eksbuild.1")<br/>  })</pre> | `{}` | no |
| az\_count | Availability zones to use. The RDS Multi-AZ DB cluster needs at least 3. | `number` | `3` | no |
| bucket\_force\_destroy | Allow terraform destroy to delete the uploads bucket even when it holds objects. | `bool` | `false` | no |
| chart\_name | Chart name in chart\_repository (preview builds are named <commit>-plane-enterprise). | `string` | `"plane-enterprise"` | no |
| chart\_repository | Helm repository of the plane-enterprise chart. Override only to test a preview build. | `string` | `"https://helm.plane.so/"` | no |
| chart\_version | plane-enterprise Helm chart version. 3.11.3 or later (configurable email Service). | `string` | `"3.11.3"` | no |
| cluster\_admin\_principal\_arns | IAM principal ARNs granted cluster-admin through EKS access entries. The identity running Terraform is added automatically. | `list(string)` | `[]` | no |
| cluster\_endpoint\_public\_access\_cidrs | CIDRs allowed to reach the public EKS API endpoint. The private endpoint is always on. Restrict this to your office, VPN or CI ranges. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| deployment\_mode | How Plane runs. Only "eks" is available in this release; "docker" (one EC2 instance with prime-cli) comes in v0.2. | `string` | `"eks"` | no |
| email | Plane's email service (inbound email to work items). On by default with its own internet-facing NLB (ports 25 SMTP,<br/>465 SMTPS, 587 submission), the sender's IP preserved. smtp\_domain is the domain that receives mail (default<br/>"intake.<domain>"): create its MX record pointing at the email\_load\_balancer\_dns\_name output (see dns\_records).<br/>Certificate: your own via certificate\_secret\_arn (a Secrets Manager secret like ingress.tls\_certificate\_secret\_arn),<br/>else the email app's own self-signed certificate (fine for receiving mail). load\_balancer = false keeps the<br/>service running with no load balancer (not reachable from the internet); enabled = false turns the service and<br/>its load balancer off. Needs plane-enterprise chart 3.11.3+. | <pre>object({<br/>    enabled                = optional(bool, true)<br/>    smtp_domain            = optional(string)<br/>    load_balancer          = optional(bool, true)<br/>    certificate_secret_arn = optional(string)<br/>  })</pre> | `{}` | no |
| enable\_components | Optional Plane workloads. pi (Plane AI) needs AI provider keys, which are set in the admin UI in this release. | <pre>object({<br/>    silo   = optional(bool, true)<br/>    drawio = optional(bool, true)<br/>    pi     = optional(bool, false)<br/>  })</pre> | `{}` | no |
| helm\_timeout | Seconds to wait for the Plane Helm release. A fresh install's migrations take about 20 minutes. | `number` | `3600` | no |
| ingress | How traffic reaches Plane. mode = "automated" (path A): the module installs Traefik behind an NLB, Plane's routes and<br/>the certificates (Let's Encrypt via acme\_email, or your own via tls\_certificate\_secret\_arn). mode = "none" (path B,<br/>default): the module installs no ingress controller or routes; you bring your controller, routes, certificate and<br/>DNS after the apply. The module configures no DNS: the records are yours in both paths (see the dns\_records output).<br/>Path A only: allowed\_cidrs (who can reach Plane), scheme (internet-facing or internal) and<br/>tls\_certificate\_secret\_arn (a Secrets Manager secret with JSON keys "tls.crt" and "tls.key", full chain, encrypted<br/>with the default aws/secretsmanager key or this module's KMS key). | <pre>object({<br/>    mode                       = optional(string, "none")<br/>    allowed_cidrs              = optional(list(string), ["0.0.0.0/0"])<br/>    scheme                     = optional(string, "internet-facing")<br/>    tls_certificate_secret_arn = optional(string)<br/>  })</pre> | `{}` | no |
| kubernetes\_version | EKS Kubernetes version. | `string` | `"1.36"` | no |
| node\_group | The managed node group: starts at desired\_size nodes and can range from min\_size to max\_size (2 to 4 by default, as<br/>today). No node autoscaler in this release, so it stays at desired\_size until scaled by hand (aws eks<br/>update-nodegroup-config --scaling-config desiredSize=N) or by an autoscaler added later. Terraform sets desired\_size<br/>only at creation and leaves later changes alone. | <pre>object({<br/>    instance_types = optional(list(string), ["m7a.xlarge"])<br/>    min_size       = optional(number, 2)<br/>    max_size       = optional(number, 4)<br/>    desired_size   = optional(number, 2)<br/>    disk_size_gb   = optional(number, 50)<br/>  })</pre> | `{}` | no |
| opensearch | Amazon OpenSearch Service for Plane's search, on by default as in today's deployments: a private domain in the VPC<br/>(HTTPS only, KMS, node-to-node encryption), reached by Plane with its Pod Identity role (SigV4, no passwords). The<br/>chart's Job creates the search indexes after every install and upgrade. enabled = false: Plane runs with search<br/>indexing off. | <pre>object({<br/>    enabled        = optional(bool, true)<br/>    engine_version = optional(string, "OpenSearch_2.19")<br/>    instance_type  = optional(string, "r7g.large.search")<br/>    instance_count = optional(number, 2)<br/>    volume_size_gb = optional(number, 10)<br/>    # Index names are "<index_prefix>_<name>", as today's deployments ("plane"). Changing it on a running install<br/>    # needs the indexes created again and re-filled (manage_search_index index create + document index).<br/>    index_prefix = optional(string, "plane")<br/>  })</pre> | `{}` | no |
| plane\_values | Extra plane-enterprise chart values (YAML string), merged last. Never put secrets here: they end up in Terraform state and the Helm release. | `string` | `""` | no |
| plane\_version | Plane release to install (chart planeVersion). | `string` | `"v4.0.1"` | no |
| postgres | RDS PostgreSQL Multi-AZ DB cluster (1 writer + 2 readable standbys), sized as today's module. | <pre>object({<br/>    engine_version        = optional(string, "15.19")<br/>    instance_class        = optional(string, "db.m6gd.large")<br/>    allocated_storage_gb  = optional(number, 100)<br/>    storage_type          = optional(string, "io1")<br/>    iops                  = optional(number, 1000)<br/>    backup_retention_days = optional(number, 14)<br/>    deletion_protection   = optional(bool, true)<br/>  })</pre> | `{}` | no |
| rabbitmq | Amazon MQ for RabbitMQ. | <pre>object({<br/>    engine_version  = optional(string, "3.13")<br/>    instance_type   = optional(string, "mq.m7g.medium")<br/>    deployment_mode = optional(string, "CLUSTER_MULTI_AZ")<br/>  })</pre> | `{}` | no |
| redis | ElastiCache Valkey with TLS, an AUTH token and at-rest encryption, as Plane's own production cache. | <pre>object({<br/>    engine_version = optional(string, "8.2")<br/>    node_type      = optional(string, "cache.t3.medium")<br/>    replicas       = optional(number, 0)<br/>  })</pre> | `{}` | no |
| single\_nat\_gateway | One shared NAT gateway (cheaper, as today's module) instead of one per AZ. | `bool` | `true` | no |
| tags | Tags applied to every AWS resource. | `map(string)` | `{}` | no |
| tls\_secret\_name | Path A: name of the Kubernetes TLS Secret in the plane namespace that Traefik serves. Written by cert-manager (acme\_email) or by External Secrets from ingress.tls\_certificate\_secret\_arn. | `string` | `"plane-tls"` | no |
| vpc\_cidr | CIDR of the VPC the module creates. Must not overlap networks you will peer or VPN with. The default avoids 10.0.0.0/16, the default of most VPC tooling and of the older aws/terraform module. | `string` | `"10.60.0.0/16"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cluster\_certificate\_authority\_data | EKS cluster CA (base64). |
| cluster\_endpoint | EKS API endpoint. |
| cluster\_name | EKS cluster name. |
| configure\_kubectl | Command to point kubectl at the cluster. |
| deployment\_mode | Deployment mode in use. |
| dns\_records | The DNS records to create (the module creates none). web: path A only; in path B, point domain at your own ingress load balancer. |
| email\_load\_balancer\_dns\_name | Hostname of the email NLB (null without email.load\_balancer). email.smtp\_domain's MX record points here. |
| kms\_key\_arn | KMS key encrypting RDS, ElastiCache, S3 and the secrets. |
| load\_balancer\_dns\_name | Path A: hostname of the Traefik NLB (null in path B). Point domain here with a CNAME (or an alias record in Route 53), never A records to its current IPs: AWS assigns them and they can change. |
| plane\_helm\_values | The plane-enterprise chart values the module generates from the infrastructure (YAML): endpoints, bucket, region, domain, load balancer and Secret names; no secret values. Excludes plane\_values. For support, debugging and reading what was installed. |
| plane\_iam\_role\_arn | IAM role Plane's pods use through EKS Pod Identity. |
| plane\_url | URL Plane is served on. |
| private\_subnet\_ids | Private subnet IDs. |
| rabbitmq\_endpoint | Amazon MQ AMQPS host. |
| rds\_endpoint | RDS cluster writer endpoint. |
| redis\_endpoint | ElastiCache primary endpoint (TLS). |
| s3\_bucket\_name | Uploads bucket. |
| secret\_arns | Secrets Manager ARNs the deployment uses (ARNs only, never values). |
| vpc\_id | VPC ID. |
<!-- END_TF_DOCS -->
