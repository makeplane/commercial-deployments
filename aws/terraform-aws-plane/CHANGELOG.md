# Changelog

## Unreleased

### Changed (breaking)
- `redis_endpoint` is now `host:port` (the ElastiCache TLS port), as on GCP and Azure.
- `dns_records` has the same keys on every cloud: `web`, `email_host` and `email_mx`. On AWS `email_host` is always
  null: the MX record names the email NLB's hostname directly.
- The chart values declare `serviceAccount.cloudIdentity: true` (Plane's ServiceAccount is bound to its role through
  EKS Pod Identity), as on GCP: it changes nothing rendered, and lets `helm upgrade` warn about settings that conflict
  with an attached identity.

### Added
- Moving an existing installation (older `aws/terraform` module + `kustomize/`): `docs/migration-guide.md`, with
  `app_keys_secret_arn` (bring the existing app keys from a Secrets Manager secret; nothing generated, the keys never
  pass through Terraform, every key required by name) and `machine_signature` (a Plane 3.x installation's signature,
  so Plane 4 can move its licences to the new instance key). The app-keys ExternalSecret now maps each key by name for
  generated keys too.
- `deployment_mode = "eks"`: VPC, EKS (fixed-size managed node group), RDS PostgreSQL Multi-AZ DB cluster,
  ElastiCache Valkey (TLS + AUTH + at-rest encryption, primary + replica with Multi-AZ failover), Amazon MQ for
  RabbitMQ, S3, KMS and Secrets Manager.
- In-cluster add-ons as Helm releases: AWS Load Balancer Controller (2.x), External Secrets, Reloader, metrics-server;
  in path A also Traefik, and cert-manager when `acme_email` is set.
- Plane (plane-enterprise chart) with secrets from Secrets Manager through External Secrets and keyless S3 through
  EKS Pod Identity.
- Load balancers with AWS-assigned IPs; their hostnames as outputs (`load_balancer_dns_name`,
  `email_load_balancer_dns_name`).
- Amazon OpenSearch Service (`opensearch.enabled`): private, KMS-encrypted, HTTPS only, keyless access from Plane
  through Pod Identity (SigV4).
- Email service on by default with its own internet-facing NLB (ports 25/465/587), the sender's IP preserved, receiving
  mail for `intake.<domain>` by default; the MX record is yours. `email.load_balancer = false` keeps the service without
  a load balancer.
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
- Two edge paths (`ingress.mode`): **automated** (path A) installs Traefik behind an NLB, Plane's routes and the
  certificates: Let's Encrypt over HTTP-01 (`acme_email`) or your own from Secrets Manager
  (`ingress.tls_certificate_secret_arn`); **none** (path B, default) installs no ingress controller or routes. The
  module configures no DNS: the `dns_records` output lists the records to create. Email certificate from Secrets
  Manager (`email.certificate_secret_arn`) in either path, else self-signed (a warning in path A).
- Every Secrets Manager ARN you pass (certificates, Plane AI keys, `app_keys_secret_arn`) is checked at plan: a full
  ARN with its 6-character suffix, in this account and region (External Secrets is granted each exact ARN).
- Plane AI set up end to end when `enable_components.pi = true` (`pi` input): chat and semantic search. Default
  `pi.provider = "api_keys"`: OpenAI chat and Cohere embeddings (or Anthropic chat, OpenAI embeddings), both keys
  required, from Secrets Manager through External Secrets. Alternative `pi.provider = "bedrock"`, keyless: application
  inference profiles for Titan Text Embeddings V2 and Claude Sonnet 4.6 (global cross-Region inference), Plane's Pod
  Identity role allowed to invoke the chat profile, and a role OpenSearch assumes to call the embeddings profile (pi
  creates the ML connector at startup). Plane AI needs OpenSearch. Plane AI's models are no longer described as configured in the admin UI: pi reads them only from its
  environment. The OpenSearch embedding dimension follows the embedding model `pi` selects whether Plane AI is on or
  off, so Plane's search indexes fit a model turned on later: choose it before the first install.
- `examples/complete`: `terraform.tfvars` is the one place to configure everything. The example declares every module
  input under the same name and passes it through; unset inputs keep the module default (`nullable = false` on every
  defaulted input). `terraform.tfvars.example` shows every setting with its default, plus a few examples. CI checks that the example declares exactly the module's inputs.
