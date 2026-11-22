# Changelog

## Unreleased

### Upgrade notes
- Installs applied from `main`: the apply that switches to the module-generated database password changes it on RDS
  before Plane's pods pick it up, so expect a short interruption on that apply: about the time External Secrets needs
  to sync the new secret (it re-reads it every minute) plus the pod restarts by Reloader. Apply it without other pending
  changes, such as a node image or Kubernetes version update.
- Installs applied from `main`: RDS already created the database log group, so the module's log group fails to create
  (`ResourceAlreadyExistsException`). Import it once, in your root module, before that apply (the module address is
  `module.<your module name>.module.data`); the apply then sets its retention, KMS key and tags, and the key applies
  to new log data only:
  ```hcl
  import {
    to = module.plane.module.data.aws_cloudwatch_log_group.postgres
    id = "/aws/rds/cluster/<name>-pg/postgresql"
  }
  ```

### Security
- Traefik chart 42.4.0 (Traefik v3.7.18), which fixes the five Traefik advisories published 2026-11-12, among them a
  path-rule bypass ([GHSA-x5pf-cqh3-2gv8](https://github.com/traefik/traefik/security/advisories/GHSA-x5pf-cqh3-2gv8),
  [GHSA-cp28-5662-543f](https://github.com/traefik/traefik/security/advisories/GHSA-cp28-5662-543f),
  [GHSA-p956-6gvv-mxqp](https://github.com/traefik/traefik/security/advisories/GHSA-p956-6gvv-mxqp),
  [GHSA-ccgh-9g52-6vwg](https://github.com/traefik/traefik/security/advisories/GHSA-ccgh-9g52-6vwg),
  [GHSA-rr42-h8r2-f28g](https://github.com/traefik/traefik/security/advisories/GHSA-rr42-h8r2-f28g)), and the denial
  of service any client could trigger on the public entry point, fixed in v3.7.17
  ([GHSA-xv5x-242w-7hf7](https://github.com/traefik/traefik/security/advisories/GHSA-xv5x-242w-7hf7)). Traefik now
  keeps accepting requests for 5 seconds after it is told to stop (the chart's new default) to avoid rollout errors.
- The api's client-IP setting now uses `TRUSTED_PROXY_IPS`, the variable the api reads (it was set as
  `TRUSTED_PROXIES`, which nothing reads, so the api trusted forwarding headers from any client). Forwarded client IPs
  are now trusted only from the VPC range (`vpc_cidr`).
- Path A: Traefik drops the `CF-Connecting-IP` and `True-Client-IP` request headers on every request (a `Middleware`
  on both entry points). Any client could set them, and the api prefers them to `X-Forwarded-For`, so a client could
  choose the IP Plane records. Behind a Cloudflare proxy, Plane now records Cloudflare's IP. Path B: your ingress should
  drop them too.

### Fixed
- `terraform destroy` no longer leaves the database log group behind with no retention: the module creates
  `/aws/rds/cluster/<name>-pg/postgresql` before the cluster (RDS then uses it, not its own), with
  `postgres.log_retention_days` (new, default 90 days as the EKS control-plane logs) and the module's KMS key. The key
  policy lets CloudWatch Logs in the region use the key for that log group only. Amazon MQ's broker log groups
  (`/aws/amazonmq/broker/<broker id>/…`) stay documented leftovers: their names hold the broker ID, known only once the
  broker exists, and Amazon MQ creates them itself (with its service-linked role), so Terraform can't own them.
- Plane AI now indexes workspace data: with `enable_components.pi` on, the module turns on pi's vector and workspace
  plan syncs (`env.pi_envs.celery.vector_sync_enabled` and `workspace_plan_sync_enabled`), which the chart leaves off;
  `plane_values` can still turn them off.
- Plane AI on Amazon OpenSearch Service: the first apply no longer fails setting the domain policy
  (`InvalidTypeException`) while IAM is still propagating the new connector role; the module waits 30 s.
- Plane AI with provider API keys can now create its embedding model on Amazon OpenSearch Service, which refused the
  Cohere connector (`Invalid Arguments in credential body`): the managed service takes no raw key in a connector, only a
  Secrets Manager secret and a role to read it. The module now creates that role in key mode too (`<name>-pi-embeddings`,
  assumable only by the module's domain, with `secretsmanager:GetSecretValue` on the embedding key's secret and
  `kms:Decrypt` with the module's KMS key through Secrets Manager), and gives Plane AI
  `AWS_OPENSEARCH_CONNECTOR_ROLE_ARN`, `AWS_OPENSEARCH_CONNECTOR_SECRET_ARN` and `AWS_OPENSEARCH_CONNECTOR_SECRET_KEY`.
  Needs a Plane AI release that keeps Cohere's `Authorization: Bearer` header in this mode.
- The connector role may also read the domain (`es:ESHttpGet`, `es:ESHttpHead`, with Bedrock too): Plane AI's setup
  signs as that role to read cluster settings, models and indexes, not only to create them.

### Changed (breaking)
- RDS no longer manages the database password: its 7-day rotation interrupted Plane each time (about 165 s), since Plane
  connects as the master user. The module generates the password, as on GCP and Azure, and stores it in its own secret
  `plane/<name>/postgres` (KMS-encrypted), which External Secrets now reads; the password is now in Terraform state.
  On an existing install the next apply changes the password on the cluster in place, RDS deletes its managed secret,
  and Plane has a one-time short interruption until its pods pick up the new password.
- With Plane AI on in key mode, `pi.api_keys.embedding_key_json_field` is required: store the Cohere key as a JSON field,
  since Amazon OpenSearch Service reads it from the secret itself. A plain-text Cohere secret is refused at plan; the
  chat key may stay plain text.
- `redis_endpoint` is now `host:port` (the ElastiCache TLS port), as on GCP and Azure.
- `dns_records` has the same keys on every cloud: `web`, `email_host` and `email_mx`. On AWS `email_host` is always
  null: the MX record names the email NLB's hostname directly.
- The chart values declare `serviceAccount.cloudIdentity: true` (Plane's ServiceAccount is bound to its role through
  EKS Pod Identity), as on GCP: it changes nothing rendered, and lets `helm upgrade` warn about settings that conflict
  with an attached identity.
- More inputs checked at plan, as on GCP: `vpc_cidr` (an IPv4 range start, /16 to /20),
  `cluster_endpoint_public_access_cidrs` and `ingress.allowed_cidrs` (at least one IPv4 CIDR, range start),
  `cluster_admin_principal_arns` (IAM role or user ARNs, no STS sessions, no repeats), `redis.replicas` (0-5),
  `postgres.engine_version` (major.minor), `postgres.storage_type` (io1, io2 or gp3) with its size and IOPS rules.
  `postgres.iops` now defaults to 1000 only for io1/io2; gp3 below 400 GiB takes none.
- PostgreSQL major version upgrades (changing `postgres.engine_version` to a new major) apply in one run: the cluster
  parameter group of the new family is created before the old one is deleted, and the cluster allows the major
  upgrade. New `postgres.apply_immediately` (default false) runs it at apply time instead of the maintenance window.
- Destroy waits for the LB controller to remove the email NLB in path B too: the add-ons' readiness (which Plane
  waits for) now depends on the NLB cleanup wait directly, not only through Traefik.
- `pi.bedrock.chat_model_id` must be a cross-Region inference profile ID (`global.` or a geography prefix such as `us.`
  or `eu.`): a bare `anthropic.claude-*` ID is rejected at plan, since current Claude models aren't served on demand in
  a single region. The Bedrock embedding models stay in-region model IDs.
- `chart_version` defaults to 3.14.0, the chart the GCP and Azure modules ship on; AWS still works from 3.11.3.
- `pi.api_keys.chat_provider = "custom"` needs `chat_base_url` and `chat_model` even with Plane AI off, as on GCP and
  Azure, so a half-set custom model is caught before Plane AI is turned on.

### Changed
- The node image no longer follows AWS's newest EKS-optimized AMI on every plan (the EKS module's
  `use_latest_ami_release_version` is off), so an unrelated apply no longer replaces the nodes. New
  `node_group.ami_release_version` (default null: keep the current release; a new node group starts on AWS's latest)
  updates them on purpose, one node at a time; see the README's "Updating node images". An existing install's next plan
  shows no node group change.

### Added
- `postgres.password_version` (default 1): bump it to rotate the RDS password on the next apply, with a short, planned
  interruption while Plane's pods pick up the new password; there is no automatic rotation. The same input as on GCP
  and Azure. The default leaves the current password unchanged on upgrade.
- `use_storage_proxy` (default false, as before): true sends work item attachments, editor images and similar through
  Plane's api instead of direct signed URLs (Plane v4.0.1 or later). silo, live and pi don't read it, and Plane AI keeps
  signed URLs in both modes, so the bucket's CORS configuration doesn't change.
- The app-keys ExternalSecret maps each key by name, so a secret missing one fails to sync rather than Plane starting
  without it.
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
- Plane v4.0.1 on plane-enterprise chart 3.14.0 by default (3.11.3 or later: configurable email Service, `/dav/` route,
  unbuffered live streaming).
  `chart_repository` and `chart_name` to test a preview build.
- Amazon OpenSearch Service on by default, as today. Search indexes are created by the chart's post-install/upgrade Job
  (3.11.3); index names use the `opensearch.index_prefix`, default `plane`, as today.
- Node group range 2–4 nodes (`node_group.min_size` / `max_size` / `desired_size`), as today, replacing the fixed `count`.
- `plane_helm_values` output: the chart values the module generates (YAML, no secret values).
- Imports run on worker-importers' own queue; the database password is re-read every minute, so a rotation reaches the
  pods quickly; api, worker, web and live replicas spread across nodes.
- Plane's background services for paid features on by default (outbox-poller, automation-consumer, runner,
  agent-consumer, webhook-consumer, iframely, worker-importers), as in today's managed deployment.
  api, worker, web and live run 2 replicas with PodDisruptionBudgets. Any attachment type allowed, as today. The
  Plane AI database job only runs when pi is on.
- Two edge paths (`ingress.mode`): **automated** (path A) installs Traefik behind an NLB, Plane's routes and the
  certificates: Let's Encrypt over HTTP-01 (`acme_email`) or your own from Secrets Manager
  (`ingress.tls_certificate_secret_arn`); **none** (path B, default) installs no ingress controller or routes. The
  module configures no DNS: the `dns_records` output lists the records to create. Email certificate from Secrets
  Manager (`email.certificate_secret_arn`) in either path, else self-signed (a warning in path A).
- Every Secrets Manager ARN you pass (certificates, Plane AI keys) is checked at plan: a full
  ARN with its 6-character suffix, in this account and region (External Secrets is granted each exact ARN).
- Plane AI set up end to end when `enable_components.pi = true` (`pi` input): chat and semantic search. Default
  `pi.provider = "api_keys"`: one chat key and Cohere embeddings. `pi.api_keys.chat_provider` picks the chat key: a
  vendor (`openai`, default; `anthropic`, `xai`, `baseten`, `meta`), whose built-in models Plane AI offers, or `custom`:
  your own model on any OpenAI-compatible API (pi's custom LLM; it requires the OpenAI Chat Completions API at
  `chat_base_url`, plus `chat_model`, optional `chat_model_name` and `chat_max_tokens`, default 128000; refused with a
  vendor). Both keys required, from Secrets Manager through External Secrets, as plain-text secrets or JSON fields (`chat_key_json_field`, `embedding_key_json_field`). Alternative `pi.provider = "bedrock"`, keyless: application
  inference profiles for Titan Text Embeddings V2 and Claude Sonnet 4.6 (global cross-Region inference), Plane's Pod
  Identity role allowed to invoke the chat profile, and a role OpenSearch assumes to call the embeddings profile (pi
  creates the ML connector at startup). Plane AI needs OpenSearch. Plane AI's models are no longer described as configured in the admin UI: pi reads them only from its
  environment. The OpenSearch embedding dimension follows the embedding model `pi` selects whether Plane AI is on or
  off, so Plane's search indexes fit a model turned on later: choose it before the first install.
- `examples/complete`: `terraform.tfvars` is the one place to configure everything. The example declares every module
  input under the same name and passes it through; unset inputs keep the module default (`nullable = false` on every
  defaulted input). `terraform.tfvars.example` shows every setting with its default, plus a few examples. CI checks that the example declares exactly the module's inputs.
