# Changelog

## Unreleased

### Added
- `deployment_mode = "gke"`: an empty GCP project to a running Plane Commercial in one apply. The module enables the
  project APIs, then builds a VPC (one subnet with GKE's ranges, Cloud NAT, private services access, flow logs), GKE
  Standard (regional, private nodes, Workload Identity, Dataplane V2, shielded nodes, release channel, cluster
  autoscaler: 3 zones × 1–2 `n2d-standard-4`), Cloud SQL for PostgreSQL 15 (regional HA, private IP, TLS required,
  backups + PITR, databases `plane` and `plane_pi`), Memorystore for Redis 7.2 (STANDARD_HA, AUTH, TLS),
  a GCS uploads bucket and Secret Manager secrets (regional replication).
- RabbitMQ and OpenSearch run in the cluster from the chart (GCP has neither as a managed service), on
  `standard-rwo` persistent disks, with generated credentials in Secret Manager synced by External Secrets. Needs
  plane-enterprise chart 3.11.6 (pending release) for the bundled RabbitMQ to read its credentials from that Secret.
- In-cluster add-ons as Helm releases: External Secrets (GCP Secret Manager through Workload Identity, CRDs kept on
  uninstall), Reloader; in path A also Traefik, and cert-manager when `acme_email` is set.
- Plane (plane-enterprise chart) with keyless GCS through GKE Workload Identity (bucket-scoped roles, signed URLs
  through the IAM signBlob API).
- Two edge paths (`ingress.mode`), as on AWS: **automated** (path A) installs Traefik behind a passthrough network
  load balancer on a reserved static IP (external, or internal with `ingress.scheme = "internal"`), Plane's routes and
  the certificates: Let's Encrypt over HTTP-01 (`acme_email`) or your own from Secret Manager
  (`ingress.tls_certificate_secret`); **none** (path B, default) installs no ingress controller or routes. The module
  configures no DNS: the `dns_records` output lists the records to create (A records to the static IPs, and an A +
  MX record for the email domain).
- Email service on by default with its own passthrough load balancer on a reserved static IP (ports 25/465/587), the
  sender's IP preserved, receiving mail for `intake.<domain>` by default. Email certificate from Secret Manager
  (`email.certificate_secret`) in either path, else self-signed (a warning in path A).
- Plane AI (pi) on GKE, off by default: `enable_components.pi = true` runs it on the GCS bucket (Plane's Workload
  Identity, no new IAM) and the in-cluster OpenSearch. New input `plane_ai`: `providers_secret`, a Secret Manager
  secret you create with the provider API keys as JSON (`COHERE_API_KEY` and/or `OPENAI_API_KEY`, `CLAUDE_API_KEY`,
  optionally `GROQ_API_KEY`), copied into the cluster by External Secrets (the keys never pass through Terraform);
  `embedding_model`, one of the 1536-dimension models (`cohere/embed-v4.0` by default,
  `openai/text-embedding-3-small`, `openai/text-embedding-ada-002`). pi needs `opensearch.enabled`, the providers secret
  and a `plane_version` whose Plane AI supports GCS (the floor is set once that release is known; until then pi is
  refused). With pi on, OpenSearch gets a 1.5 GB heap in a 3 GiB limit, which needs plane-enterprise chart 3.11.6.
- `plane_helm_values` output: the chart values the module generates (YAML, no secret values).
- `examples/complete`: `terraform.tfvars` is the one place to configure everything; the example declares every module
  input under the same name (`nullable = false` on every defaulted input). CI checks that it declares exactly the
  module's inputs.
- `terraform test` suites with mock providers (edge paths, add-ons, Plane values) and a CI workflow (fmt, validate,
  test, tflint, checkov, terraform-docs).
