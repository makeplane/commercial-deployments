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
- `examples/complete`.
