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

- Terraform ≥ 1.9 and the **AWS CLI v2** (Helm authenticates to EKS with `aws eks get-token`).
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
<!-- END_TF_DOCS -->
