# terraform-aws-plane

Terraform module that deploys [Plane](https://plane.so) Commercial on AWS with one `terraform apply`: the network,
an EKS cluster, managed data services and Plane itself (the `plane-enterprise` Helm chart).

> **Status:** under development (INFRA-1261). Published to the Terraform Registry as `makeplane/plane/aws` from
> `v0.1.0`. Until then, reference it from this repository. It doesn't change or replace the older `aws/terraform`
> module or the `kustomize/` setup.

## What it creates

| Layer | Resources | Defaults |
|---|---|---|
| Network | VPC, 3 private + 3 public subnets, NAT, S3 gateway endpoint, flow logs | Workloads only in private subnets; one shared NAT gateway |
| Cluster | EKS (access entries, secrets encryption, control-plane logs), one managed node group, managed add-ons (vpc-cni, coredns, kube-proxy, Pod Identity agent, EBS CSI) | Kubernetes 1.36, 2 × m7a.xlarge, fixed size (no autoscaler) |
| PostgreSQL | RDS for PostgreSQL **Multi-AZ DB cluster** (1 writer + 2 readable standbys) | 15.19, `db.m6gd.large`, 100 GB io1 / 1000 IOPS, KMS, TLS required, master password managed by RDS |
| Cache | ElastiCache **Valkey** | 8.2, `cache.t3.medium`, TLS + AUTH token + at-rest encryption |
| Queue | Amazon MQ for RabbitMQ | 3.13, `mq.m7g.medium`, multi-AZ cluster, AMQPS only, private |
| Storage | S3 uploads bucket | SSE-KMS, no public access, TLS-only policy, versioning, CORS for your domain |
| Secrets | Secrets Manager (Valkey token, MQ user, app keys) + the RDS-managed master secret | KMS-encrypted; values never pass through Terraform variables |
| Edge | NLB on static Elastic IPs → Traefik; TLS terminated by Traefik | Route 53 A record + Let's Encrypt via cert-manager when you give a hosted zone |
| In cluster (Helm) | AWS Load Balancer Controller 2.x, Traefik, External Secrets, Reloader, metrics-server, cert-manager (Route 53 only), **plane-enterprise** | Pods reach S3 and Secrets Manager through **EKS Pod Identity**: no IAM users, no access keys |

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
      args        = ["eks", "get-token", "--cluster-name", module.plane.cluster_name]
    }
  }
}

module "plane" {
  source = "git::https://github.com/makeplane/commercial-deployments.git//aws/terraform-aws-plane?ref=<tag>"

  name            = "plane"
  domain          = "plane.example.com"
  route53_zone_id = "Z0123456789ABCDEFGHIJ" # optional, see "DNS and TLS"
  acme_email      = "ops@example.com"
}
```

A full example is in [`examples/complete`](examples/complete).

## Prerequisites

- Terraform ≥ 1.10 (S3 state locking with `use_lockfile`) and the **AWS CLI v2** (Helm authenticates to EKS with `aws eks get-token`).
- Credentials allowed to create VPC, EKS, IAM roles, RDS, ElastiCache, Amazon MQ, S3, KMS, Secrets Manager,
  Elastic IPs and (with a zone) Route 53 records.
- Network access from where you run Terraform to the EKS API endpoint. It's public by default; restrict it with
  `cluster_endpoint_public_access_cidrs`.
- An **encrypted remote state backend**. State holds generated secrets (Valkey token, MQ password, app keys).
- Service quotas for at least 4 Elastic IPs (3 for the load balancer, 1 for the NAT gateway).

## DNS and TLS

**With `route53_zone_id`:** the module creates the A record pointing at the load balancer's static IPs and issues a
Let's Encrypt certificate with cert-manager (DNS-01). Nothing to do by hand. Set `acme_email`.

**Without a zone (manual step):**
1. `terraform apply`. Plane comes up serving Traefik's default certificate.
2. Point your domain at the `public_ips` output (A records), in whatever DNS you use.
3. Create the certificate Secret Traefik serves:
   ```bash
   aws eks update-kubeconfig --name <cluster_name> --region <region>   # see the configure_kubectl output
   kubectl -n plane create secret tls plane-tls --cert=fullchain.pem --key=privkey.pem
   ```
4. Traefik picks it up without a restart. Replace the Secret before it expires.

## After install

Open `https://<domain>`, finish the setup wizard, then activate your licence in the admin UI. SMTP, SSO and AI provider
keys are configured in the admin UI (`/god-mode`) in this release.

## Things to know

- **Never change `domain`, the namespace or the release name.** They're part of Plane's licence identity. The release
  and namespace are fixed to `plane`.
- **App keys are generated once and never rotated** (`plane/<name>/app-keys`). Changing them makes stored encrypted
  data unreadable.
- **The node group has a fixed size.** Change `node_group.count` and re-apply to scale.
- **Destroying:** RDS deletion protection is on. Set `postgres = { deletion_protection = false }`, apply, then
  destroy. The bucket is kept unless it's empty or `bucket_force_destroy = true`.
- **Known gap:** the live service's export queue doesn't connect to RabbitMQ when broker credentials come from a
  Secret (a chart fix is pending).

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
| acme\_email | Let's Encrypt account email. Required when route53\_zone\_id is set (the module then issues the certificate itself). | `string` | `null` | no |
| acme\_server | ACME directory URL. Use the Let's Encrypt staging URL for tests to avoid rate limits. | `string` | `"https://acme-v02.api.letsencrypt.org/directory"` | no |
| addon\_versions | EKS managed add-on versions. null for an add-on means the most recent version for kubernetes\_version. | <pre>object({<br/>    vpc_cni                = optional(string, "v1.23.2-eksbuild.8")<br/>    coredns                = optional(string, "v1.14.7-eksbuild.22")<br/>    kube_proxy             = optional(string, "v1.36.0-eksbuild.58")<br/>    eks_pod_identity_agent = optional(string, "v1.4.1-eksbuild.3")<br/>    aws_ebs_csi_driver     = optional(string, "v1.67.2-eksbuild.1")<br/>  })</pre> | `{}` | no |
| allowed\_cidrs | Source CIDRs allowed to reach Plane on 443/80 through the load balancer. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| az\_count | Availability zones to use. The RDS Multi-AZ DB cluster needs at least 3. | `number` | `3` | no |
| bucket\_force\_destroy | Allow terraform destroy to delete the uploads bucket even when it holds objects. | `bool` | `false` | no |
| chart\_version | plane-enterprise Helm chart version. | `string` | `"3.11.1"` | no |
| cluster\_admin\_principal\_arns | IAM principal ARNs granted cluster-admin through EKS access entries. The identity running Terraform is added automatically. | `list(string)` | `[]` | no |
| cluster\_endpoint\_public\_access\_cidrs | CIDRs allowed to reach the public EKS API endpoint. The private endpoint is always on. Restrict this to your office, VPN or CI ranges. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| deployment\_mode | How Plane runs. Only "eks" is available in this release; "docker" (one EC2 instance with prime-cli) comes in v0.2. | `string` | `"eks"` | no |
| enable\_components | Optional Plane workloads. pi (Plane AI) needs AI provider keys, which are set in the admin UI in this release. | <pre>object({<br/>    silo   = optional(bool, true)<br/>    drawio = optional(bool, true)<br/>    pi     = optional(bool, false)<br/>  })</pre> | `{}` | no |
| helm\_timeout | Seconds to wait for the Plane Helm release. A fresh install's migrations take about 20 minutes. | `number` | `3600` | no |
| kubernetes\_version | EKS Kubernetes version. | `string` | `"1.36"` | no |
| node\_group | The managed node group. Fixed size (no autoscaler in this release): change count and re-apply to scale. | <pre>object({<br/>    instance_types = optional(list(string), ["m7a.xlarge"])<br/>    count          = optional(number, 2)<br/>    disk_size_gb   = optional(number, 50)<br/>  })</pre> | `{}` | no |
| plane\_values | Extra plane-enterprise chart values (YAML string), merged last. Never put secrets here: they end up in Terraform state and the Helm release. | `string` | `""` | no |
| plane\_version | Plane release to install (chart planeVersion). | `string` | `"v4.0.0"` | no |
| postgres | RDS PostgreSQL Multi-AZ DB cluster (1 writer + 2 readable standbys), sized as today's module. | <pre>object({<br/>    engine_version        = optional(string, "15.19")<br/>    instance_class        = optional(string, "db.m6gd.large")<br/>    allocated_storage_gb  = optional(number, 100)<br/>    storage_type          = optional(string, "io1")<br/>    iops                  = optional(number, 1000)<br/>    backup_retention_days = optional(number, 14)<br/>    deletion_protection   = optional(bool, true)<br/>  })</pre> | `{}` | no |
| rabbitmq | Amazon MQ for RabbitMQ. | <pre>object({<br/>    engine_version  = optional(string, "3.13")<br/>    instance_type   = optional(string, "mq.m7g.medium")<br/>    deployment_mode = optional(string, "CLUSTER_MULTI_AZ")<br/>  })</pre> | `{}` | no |
| redis | ElastiCache Valkey with TLS, an AUTH token and at-rest encryption, as Plane's own production cache. | <pre>object({<br/>    engine_version = optional(string, "8.2")<br/>    node_type      = optional(string, "cache.t3.medium")<br/>    replicas       = optional(number, 0)<br/>  })</pre> | `{}` | no |
| route53\_zone\_id | Public Route 53 hosted zone that contains domain. When set, the module writes the A record and issues the certificate<br/>(cert-manager, DNS-01). When null, DNS and the certificate are a manual step: see the README. | `string` | `null` | no |
| single\_nat\_gateway | One shared NAT gateway (cheaper, as today's module) instead of one per AZ. | `bool` | `true` | no |
| tags | Tags applied to every AWS resource. | `map(string)` | `{}` | no |
| tls\_secret\_name | Kubernetes TLS Secret in the plane namespace that Traefik serves. Written by cert-manager when route53\_zone\_id is set; created by the operator otherwise. | `string` | `"plane-tls"` | no |
| vpc\_cidr | CIDR of the VPC the module creates. | `string` | `"10.0.0.0/16"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cluster\_certificate\_authority\_data | EKS cluster CA (base64). |
| cluster\_endpoint | EKS API endpoint. |
| cluster\_name | EKS cluster name. |
| configure\_kubectl | Command to point kubectl at the cluster. |
| deployment\_mode | Deployment mode in use. |
| dns\_record\_managed | Whether the module manages the DNS record (true when route53\_zone\_id is set). |
| kms\_key\_arn | KMS key encrypting RDS, ElastiCache, S3 and the secrets. |
| plane\_iam\_role\_arn | IAM role Plane's pods use through EKS Pod Identity. |
| plane\_url | URL Plane is served on. |
| private\_subnet\_ids | Private subnet IDs. |
| public\_ips | Static public IPs of the load balancer. Point domain here when route53\_zone\_id is null. |
| rabbitmq\_endpoint | Amazon MQ AMQPS host. |
| rds\_endpoint | RDS cluster writer endpoint. |
| redis\_endpoint | ElastiCache primary endpoint (TLS). |
| s3\_bucket\_name | Uploads bucket. |
| secret\_arns | Secrets Manager ARNs the deployment uses (ARNs only, never values). |
| vpc\_id | VPC ID. |
<!-- END_TF_DOCS -->
