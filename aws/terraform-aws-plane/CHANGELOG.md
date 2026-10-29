# Changelog

## Unreleased

### Added
- `deployment_mode = "eks"`: VPC, EKS (fixed-size managed node group), RDS PostgreSQL Multi-AZ DB cluster,
  ElastiCache Valkey (TLS + AUTH + at-rest encryption), Amazon MQ for RabbitMQ, S3, KMS and Secrets Manager.
- In-cluster add-ons as Helm releases: AWS Load Balancer Controller (2.x), Traefik, External Secrets, Reloader,
  metrics-server, and cert-manager when a Route 53 zone is given.
- Plane (plane-enterprise chart) with secrets from Secrets Manager through External Secrets, keyless S3 through
  EKS Pod Identity, and TLS from cert-manager (Route 53) or a certificate the operator provides.
- `examples/complete`.
