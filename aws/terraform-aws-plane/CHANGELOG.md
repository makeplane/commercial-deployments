# Changelog

## Unreleased

### Added
- `deployment_mode = "eks"`: VPC, EKS (fixed-size managed node group), RDS PostgreSQL Multi-AZ DB cluster,
  ElastiCache Valkey (TLS + AUTH + at-rest encryption), Amazon MQ for RabbitMQ, S3, KMS and Secrets Manager.
- In-cluster add-ons as Helm releases: AWS Load Balancer Controller (2.x), Traefik, External Secrets, Reloader,
  metrics-server, and cert-manager when `acme_email` is set.
- Plane (plane-enterprise chart) with secrets from Secrets Manager through External Secrets, keyless S3 through
  EKS Pod Identity, and TLS from cert-manager (Let's Encrypt: DNS-01 with a Route 53 zone, HTTP-01 without one) or
  a certificate the operator provides.
- Load balancer with AWS-assigned IPs; `load_balancer_dns_name` output for DNS outside Route 53.
- Amazon OpenSearch Service (`opensearch.enabled`): private, KMS-encrypted, HTTPS only, keyless access from Plane
  through Pod Identity (SigV4).
- Email service on by default with its own internet-facing NLB (ports 25/465/587), the sender's IP preserved, receiving
  mail for `intake.<domain>` by default; MX record and Let's Encrypt certificate with a Route 53 zone, the email app's
  self-signed certificate otherwise. `email.load_balancer = false` keeps the service without a load balancer.
- Plane v4.0.1 on plane-enterprise chart 3.11.3 (configurable email Service, `/dav/` route, unbuffered live streaming).
  `chart_repository` and `chart_name` to test a preview build.
- Amazon OpenSearch Service on by default, as today. Search indexes are created by the chart's post-install/upgrade Job
  (3.11.3); index names use the `opensearch.index_prefix`, default `plane`, as today.
- Node group range 2–4 nodes (`node_group.min_size` / `max_size` / `desired_size`), as today, replacing the fixed `count`.
- `plane_helm_values` output: the chart values the module generates (YAML, no secret values).
- Imports run on worker-importers' own queue; the RDS-managed database password is re-read every minute (RDS rotates it
  every 7 days); api, worker, web and live replicas spread across nodes.
- Plane's background services for paid features on by default (outbox-poller, automation-consumer, runner,
  agent-consumer, webhook-consumer, iframely, worker-importers), as in today's managed deployment.
  api, worker, web and live run 2 replicas with PodDisruptionBudgets. Any attachment type allowed, as today. The
  Plane AI database job only runs when pi is on.
- `examples/complete`: `terraform.tfvars` is the one place to configure everything. The example declares every module
  input under the same name and passes it through; unset inputs keep the module default (`nullable = false` on every
  defaulted input). `terraform.tfvars.example` shows every setting with its default, plus a few examples. CI checks that the example declares exactly the module's inputs.
