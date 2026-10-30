# Plane Terraform modules: roadmap

Use this to decide what goes into the next releases. It assumes **v0.1.0 of the AWS module is published** and its
PRs are merged. Details behind each item are in [AWS-MODULE-PLAN.md](AWS-MODULE-PLAN.md),
[AWS-EDGE-DESIGN.md](AWS-EDGE-DESIGN.md) and [AWS-TODAY-VS-MODULE.md](AWS-TODAY-VS-MODULE.md).

## 1. Released: v0.1.0 (AWS, EKS)

`makeplane/plane/aws` on the Terraform Registry: an AWS account to a running Plane Commercial with one
`terraform apply`, on plane-enterprise chart 3.11.3.

| Area | In v0.1.0 |
|---|---|
| Infrastructure | VPC, EKS, RDS Multi-AZ DB cluster, ElastiCache Valkey, Amazon MQ, OpenSearch, S3, KMS, Secrets Manager. Pod Identity throughout, no static keys |
| Plane | Today's managed-deployment services; search indexes created automatically on install and upgrade |
| Edge | Path A (Traefik + Let's Encrypt, or your own certificates from Secrets Manager); path B (bring your own ingress). Internal web load balancer with `ingress.scheme = "internal"` (A.2 or path B). DNS is always the customer's: the `dns_records` output lists the records |
| Email | Email service + its own load balancer, certificate from Secrets Manager or self-signed |
| Configuration | One place (`terraform.tfvars`); every input documented with its default |
| Quality | Static checks, checkov, `terraform test`, verified end to end on the dev account |
| Docs | Module README, customer deployment guide |

**Known limits of v0.1.0** (addressed in the roadmap below): new installs only; the module always creates its own VPC
and cluster; no node or pod autoscaling; images pulled from Docker Hub anonymously; SMTP, SSO and AI keys are set in
the admin UI; the EKS API endpoint is public by default; one module-managed KMS key; backups are RDS automated backups
and a final snapshot only; RabbitMQ 3.13; releases are tested by hand. The email load balancer stays internet-facing.

## 2. Next: v0.2.0 and later

The next targeted items, in order. No dates; each release takes the next items that are ready.

1. **Docker mode:** Plane on one EC2 instance with prime-cli and Docker Compose, bundled data services, plus a
   Quickstart template. Its edge (A12: Caddy + Elastic IP, or ALB + ACM) is decided when the work starts.
2. **GCP module** (`terraform-google-plane`): same layout and edge model as AWS.
3. **Release CI with e2e:** apply, smoke test and destroy on every tag.
4. **Path B route files** per chart release (Traefik, NGINX, OpenShift) and a route table.
5. **Least-privilege IAM policy** for the deploying role.
6. **Bring your own VPC first, then your own cluster** (T4).
7. **Node autoscaling** (G-E1): Cluster Autoscaler on the managed node group's 2–4 range first; Karpenter or EKS Auto
   Mode later.
8. **Pod autoscaling:** revive chart HPA PR helm-charts#133 for api, worker, agent-consumer and webhook-consumer
   (CPU, 2–5). Ship it with node autoscaling.
9. **Restricted EKS API endpoint** by default.
10. **`extra_secrets`** (A20): an `extra_secrets` input → External Secrets → the chart's `*_existingSecret`, so SMTP,
    SSO, AI and integration keys come from Secrets Manager instead of the admin UI.
11. **Image pulls** (A19, G-E3): images come from Docker Hub anonymously, so rate limits apply through one NAT IP.
    Optional authenticated pulls first, then an ECR pull-through cache.
12. **Dedicated database user** or Plane's `RDS_SECRET_ARN` support.
13. **Version and upgrade policy** (A27): pin and upgrade EKS, add-ons, the chart and Plane through module releases;
    Renovate on templates; a pre-upgrade RDS snapshot and a rollback runbook.
14. **AWS Backup plan** as an option (A25).
15. **KMS options:** a `kms_key_arn` input (bring your own key) and optional per-service keys.
16. **RabbitMQ 4.x** (A28): move once Plane supports it on Amazon MQ.
17. **Observability** option (CloudWatch add-on).
18. **Pinned Elastic IPs** for the web load balancer.
19. **Sizing data, then size presets** (A26): measure load on dev or on Plane's own installation before setting
    larger defaults and presets.
20. **Azure module** (`terraform-azurerm-plane`), once Azure Blob storage is supported.
21. **Migration guide** from today's Kustomize installs.

**Not planned:** DNS automation. DNS is always the customer's and the `dns_records` output lists the records. Revisit
only on demand (for example, an optional Route 53 record).
