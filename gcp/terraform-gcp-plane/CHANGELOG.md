# Changelog

## Unreleased

### Security
- Traefik chart 42.3.1 (Traefik v3.7.17), which fixes a denial of service any client could trigger on the public
  entry point ([GHSA-xv5x-242w-7hf7](https://github.com/traefik/traefik/security/advisories/GHSA-xv5x-242w-7hf7)).

### Changed
- Terraform Registry name `terraform-gcp-plane` (`makeplane/plane/gcp`), the same as its folder and its
  `managed-by` label.
- `chart_version` defaults to plane-enterprise 3.14.0 (pending release in
  [helm-charts#377](https://github.com/makeplane/helm-charts/pull/377)), which carries the chart changes this module
  needs; 3.12.2 was never released.
- `ingress.allowed_cidrs` is checked at plan, as on AWS: at least one IPv4 CIDR whose address is the start of the range
  (`203.0.113.10/32` for one address).
- The checks on `pi.api_keys` for `chat_provider = "custom"` match AWS and Azure: `chat_base_url`, `chat_model`,
  `chat_model_name` and `chat_max_tokens` are refused with a vendor key; `custom` needs `chat_base_url` and a non-blank
  `chat_model`.
- On the RAPID and REGULAR release channels the GKE cluster is created without a default node pool, so the plan no
  longer shows the google provider's `remove_default_node_pool` deprecation warning. STABLE is unchanged (its GKE
  versions still need the old way), and changing channel later doesn't recreate the cluster.
- TLS to Memorystore is always on, as on AWS and Azure: `redis.transit_encryption` is removed, and a value left in
  `terraform.tfvars` is ignored. An instance created with it off is replaced on the next apply.
- `opensearch.volume_size_gb` defaults to 50 (was 20), as on Azure. The size can't change on an existing install: to
  keep one installed at 20, set `opensearch = { volume_size_gb = 20 }`, or the Helm upgrade fails.
- `use_storage_proxy` docs corrected: `true` moves attachments, editor images and similar to Plane's api, but silo, live
  and pi don't read it and Plane AI keeps signed URLs, so the bucket keeps its CORS configuration.

### Fixed
- `examples/complete` outputs `secret_ids`, which the deployment guide uses.
- Deployment guide: Plane AI's keys, `jq` use, `terraform init` when upgrading, the `null` values in `dns_records`, and
  keeping other `postgres` fields when preparing to destroy.

### Added
- `deployment_mode = "gke"`: an empty GCP project to a running Plane Commercial in one apply. The module enables the
  project APIs, then builds a VPC (one subnet with GKE's ranges, Cloud NAT, private services access, flow logs), GKE
  Standard (regional, private nodes, Workload Identity, Dataplane V2, shielded nodes, release channel, cluster
  autoscaler: 3 zones × 1–2 `n2d-standard-4`), Cloud SQL for PostgreSQL 15 (regional HA, private IP, TLS required,
  backups + PITR, a final backup on delete kept 30 days, databases `plane` and `plane_pi`), Memorystore for Redis 7.2
  (STANDARD_HA, AUTH, TLS, daily RDB snapshots),
  a GCS uploads bucket and Secret Manager secrets (regional replication).
- RabbitMQ and OpenSearch run in the cluster from the chart (GCP has neither as a managed service), on
  `standard-rwo` persistent disks, with generated credentials in Secret Manager synced by External Secrets. Needs
  plane-enterprise chart 3.14.0 (pending release, helm-charts#377) for the bundled RabbitMQ to read its credentials
  from that Secret.
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
  Identity, no new IAM) and the in-cluster OpenSearch, with chat and semantic search (`pi` input). Chat on a vendor
  key (`pi.api_keys.chat_provider`: `openai`, the default, `anthropic`, `xai`, `baseten` or `meta`), with that vendor's
  built-in models, or `custom`: your own model on any OpenAI-compatible API (Plane AI's custom LLM; requires the OpenAI
  Chat Completions API at `chat_base_url`, with `chat_model`, and optionally `chat_model_name` and `chat_max_tokens`,
  default 128000). Embeddings on Cohere (`cohere/embed-v4.0` by default, or another Cohere model). The search indexes'
  dimension (`OPENSEARCH_EMBEDDING_DIMENSION`) follows `pi.api_keys.embedding_model`, with pi on or off (1536 by
  default). Both keys are required, each a Secret Manager secret in `project_id`, plain text or a JSON field
  (`chat_key_json_field`, `embedding_key_json_field`; one JSON secret can hold both), copied by External Secrets into
  the env var Plane AI reads, in the Secret the chart mounts on the Plane AI workloads (the keys never pass through
  Terraform). pi needs
  `opensearch.enabled` and a `plane_version` whose Plane AI supports GCS (the floor is set once that release is known;
  until then pi is refused). With pi on, OpenSearch gets a 1.5 GB heap in a 3 GiB limit, which needs plane-enterprise
  chart 3.14.0.
- `plane_helm_values` output: the chart values the module generates (YAML, no secret values).
- `examples/complete`: `terraform.tfvars` is the one place to configure everything; the example declares every module
  input under the same name (`nullable = false` on every defaulted input). CI checks that it declares exactly the
  module's inputs.
- `terraform test` suites with mock providers (edge paths, add-ons, Plane values) and a CI workflow (fmt, validate,
  test, tflint, checkov, terraform-docs).
