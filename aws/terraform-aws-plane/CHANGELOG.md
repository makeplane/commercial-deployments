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
- Optional Amazon OpenSearch Service (`opensearch.enabled`, off by default): private, KMS-encrypted, HTTPS only, keyless
  access from Plane through Pod Identity (SigV4).
- Email service on by default with no load balancer, as today; `email.load_balancer` gives it its own internet-facing
  NLB (ports 25/465/587) with the sender's IP preserved; MX record and Let's Encrypt certificate with a Route 53 zone,
  the email app's self-signed certificate otherwise.
- plane-enterprise chart 3.11.2 (configurable email Service, `/dav/` route). `chart_repository` and `chart_name` to test
  a preview build.
- Plane's background services for paid features on by default (outbox-poller, automation-consumer, runner,
  agent-consumer, webhook-consumer, iframely, external-api, worker-importers), as in today's managed deployment.
  api, worker, web and live run 2 replicas with PodDisruptionBudgets. Any attachment type allowed, as today. The
  Plane AI database job only runs when pi is on.
- `examples/complete`.
