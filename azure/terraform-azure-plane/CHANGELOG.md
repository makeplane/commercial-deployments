# Changelog

## Unreleased

### Security
- Traefik chart 42.4.0 (Traefik v3.7.18), which fixes the advisories published 2026-11-12, including a path-rule
  bypass ([GHSA-x5pf-cqh3-2gv8](https://github.com/traefik/traefik/security/advisories/GHSA-x5pf-cqh3-2gv8),
  [GHSA-cp28-5662-543f](https://github.com/traefik/traefik/security/advisories/GHSA-cp28-5662-543f),
  [GHSA-p956-6gvv-mxqp](https://github.com/traefik/traefik/security/advisories/GHSA-p956-6gvv-mxqp),
  [GHSA-ccgh-9g52-6vwg](https://github.com/traefik/traefik/security/advisories/GHSA-ccgh-9g52-6vwg),
  [GHSA-rr42-h8r2-f28g](https://github.com/traefik/traefik/security/advisories/GHSA-rr42-h8r2-f28g)), and the denial
  of service any client could trigger on the public entry point fixed in v3.7.17
  ([GHSA-xv5x-242w-7hf7](https://github.com/traefik/traefik/security/advisories/GHSA-xv5x-242w-7hf7)). The chart now
  keeps accepting requests for 5 seconds after a Traefik pod is told to stop, so rollouts drop fewer connections.
- The api's client-IP setting now uses the variable the api reads (`TRUSTED_PROXY_IPS`, was `TRUSTED_PROXIES`), so
  forwarded client IPs are trusted only from the pod range (Traefik's pods), not from any client.
- Path A: Traefik removes the `CF-Connecting-IP` and `True-Client-IP` request headers on both entry points (a
  `Middleware` shipped with the Traefik release), so a client can no longer set the IP Plane records: the api prefers
  them to `X-Forwarded-For`. Traefik already replaces a client-sent `X-Real-IP` and `X-Forwarded-For`. In path B, your
  ingress should drop the client-sent `CF-Connecting-IP`, `True-Client-IP` and `X-Real-IP` and not pass a client-sent
  `X-Forwarded-For` through (see README).

> **Not releasable yet.** Needs Plane's native Azure Blob storage support (api and silo) and plane-enterprise chart
> 3.14.0 ([helm-charts#377](https://github.com/makeplane/helm-charts/pull/377), pending release), which renders it
> and lets the bundled RabbitMQ read `external_secrets.rabbitmq`. The Blob chart values follow the **agreed contract**
> (`modules/plane/main.tf`, "AZURE BLOB STORAGE"); the `plane_version` (`v4.0.1`) and `chart_version` (`3.14.0`)
> defaults are placeholders until those releases exist, and the Blob floor refuses the `plane_version` default at
> plan. See README, "Requires".

### Added
- `postgres.password_version` (default 1): bump it to rotate the PostgreSQL password on the next apply, with a short,
  planned interruption while Plane's pods pick up the new password; there is no automatic rotation. The same input as
  on AWS and GCP. The default leaves the current password unchanged on upgrade.
- `deployment_mode = "aks"`: resource group (or an existing empty one), VNet with NAT gateway egress, AKS (Entra ID +
  Azure RBAC, local accounts off, Workload Identity, Azure CNI Overlay with Cilium, one autoscaled node pool),
  PostgreSQL Flexible Server 15 (VNet-integrated, TLS required, zone-redundant HA, delete lock, databases `plane` and
  `plane_pi` created by Terraform: no DB-init Job), Azure Managed Redis (private endpoint, TLS), Key Vault (RBAC, purge
  protection) with the generated secrets. Platform-managed encryption keys.
- Native **Azure Blob** uploads storage: StorageV2 account without shared keys or public access, private endpoint,
  ZRS, versioning and soft delete, delete lock (`storage`). Plane's pods use a user-assigned managed identity federated
  to `plane/plane-srv-account` with Storage Blob Data Contributor on the container; proxy-only (no SAS, no CORS).
- In-cluster RabbitMQ and OpenSearch from the chart (Azure has no managed equivalents) on a zone-redundant Premium SSD
  StorageClass shipped as a chart extraObject (`persistent_volume_sku`); their credentials come from Key Vault through
  External Secrets (no secret values in Helm values).
- In-cluster add-ons as Helm releases: External Secrets (Workload Identity, CRDs kept on uninstall) and Reloader; in
  path A also Traefik, and cert-manager when `acme_email` is set. AKS provides metrics-server and the load balancer
  integration.
- The same edge model as the AWS module: `ingress.mode` **automated** (path A: Traefik on a static public IP, or a
  fixed private IP with `ingress.scheme = "internal"`; Let's Encrypt HTTP-01 or your Key Vault certificate via
  `ingress.tls_certificate_secret_id`) or **none** (path B, default). No DNS records, no DNS-01, no zone input: the
  `dns_records` output lists the A and MX records to create.
- Email service on by default with its own static public IP (ports 25/465/587, sender IP preserved), certificate from
  Key Vault (`email.certificate_secret_id`) or self-signed.
- `plane_version` is checked at plan against the first Plane release with the Azure Blob storage backend, as Plane AI's
  floor is: an older release (including the current `v4.0.1` default) is refused with an error, instead of installing
  a Plane whose uploads fail at runtime. The floor is a placeholder (`v99.0.0`) until that release is known; build
  tags (branch or preview builds) aren't checked.
- `api_server_authorized_ip_ranges`, when set, also allows the cluster's NAT egress IP (`/32`), as the Key Vault
  firewall does: with a NAT gateway AKS doesn't add it, and the nodes and in-cluster add-ons would be refused. Empty
  still leaves the API server unrestricted.
- Every Key Vault certificate ID you pass (`ingress.tls_certificate_secret_id`, `email.certificate_secret_id`) is checked
  at plan: a full, versionless resource ID in this subscription. `cluster_admin_object_ids` must be GUIDs.
- Plane AI (pi) on AKS, off by default: `enable_components.pi = true` runs it on the Blob container (Plane's Workload
  Identity) and the in-cluster OpenSearch, with chat and semantic search (`pi` input). Chat on a vendor key
  (`pi.api_keys.chat_provider`: `openai` by default, `anthropic`, `xai`, `baseten` or `meta`; that vendor's models, Plane
  AI picks the default) or `custom`: your own model on any OpenAI-compatible API (Plane AI's custom LLM; `chat_base_url`,
  `chat_model`, optional `chat_model_name` and `chat_max_tokens`, default 128000), such as Azure OpenAI's `/openai/v1`
  endpoint. `custom` requires the OpenAI Chat Completions API at `chat_base_url`; the module refuses the `custom` inputs
  with a vendor. Embeddings on Cohere (`cohere/embed-v4.0` by default, or another Cohere model). The search indexes'
  dimension (`OPENSEARCH_EMBEDDING_DIMENSION`) follows `pi.api_keys.embedding_model`, with pi on or off (1536 by
  default). Both keys are required, in one Key Vault of yours, by ID, as plain-text secrets or JSON fields
  (`chat_key_json_field`, `embedding_key_json_field`; one JSON secret can hold both): External Secrets gets read on
  those secrets only and copies them into the env var Plane AI reads, in the Secret the chart mounts on Plane AI
  (`external_secrets.ai_providers_existingSecret`; the keys never pass through Terraform). pi needs `opensearch.enabled` and a `plane_version` whose Plane AI supports Azure
  Blob (the floor is set once that release is known; until then pi is refused, except on preview tags). With pi on,
  OpenSearch gets a 1.5 GB heap in a 3 GiB limit.
- Aligned with the AWS and GCP modules: `redis.sku_name` defaults to `Balanced_B3` (was `Balanced_B1`); `redis.persistence`
  (default true) saves an RDB snapshot every 12 hours and needs `redis.high_availability_enabled`; with
  `storage.versioning_enabled`, a lifecycle policy deletes previous blob versions 30 days after they were first written;
  `serviceAccount.cloudIdentity = true` in the chart values; `dns_records` web and email A records carry the
  "DNS-only, no proxy" hint.
- `use_storage_proxy` input (default true). Azure supports only true, and the module refuses false: the storage account
  is private and the module uses no SAS or CORS.
- Removed `rabbitmq.mode` and `opensearch.mode`, which accepted only `"in-cluster"`.
- A complete [deployment guide](docs/deployment-guide.md), and more outputs in `examples/complete` for the commands it
  uses (`resource_group_name`, `nat_public_ip`, `postgres_endpoint`, `storage_account_name`, `key_vault_uri`).
- `examples/complete` declares every module input 1:1 (`terraform.tfvars.example` shows every default); mock-provider
  tests (`tests/*.tftest.hcl`) for the edge paths, add-ons, the generated chart values, the data layer, the AKS API
  allow-list and the `plane_version` floors; CI workflow `terraform-azure-plane.yml` (fmt, validate, test, tflint,
  checkov, terraform-docs, example inputs).

### Changed
- README: known issues and notes from the first end-to-end test (Plane AI setup, indexing, custom models, the embedding
  key, outgoing email).
- The `plane-db` ExternalSecret re-reads the database password every minute (was hourly), so a
  `postgres.password_version` rotation reaches Plane in about a minute, as on AWS. The other secrets stay hourly.
- Terraform Registry name `terraform-azure-plane` (`makeplane/plane/azure`), the same as its folder and its
  `managed-by` tag.
- `kubernetes_version` defaults to AKS 1.36 (was 1.35), GA and the AKS default for new clusters.
- `chart_version` defaults to plane-enterprise 3.14.0
  ([helm-charts#377](https://github.com/makeplane/helm-charts/pull/377), pending release), which ships the Azure Blob
  values and the bundled RabbitMQ external secret (was 3.12.2, never released).
- `ingress.allowed_cidrs` is checked at plan, as on AWS: at least one IPv4 CIDR whose address is the start of its range
  (`203.0.113.10/32` for one address).
- `pi.api_keys` custom-chat checks aligned with the AWS module: `chat_provider = "custom"` needs `chat_base_url` and
  `chat_model`, and the custom-only inputs are refused with a vendor key.
- The in-cluster OpenSearch credentials Secret is named `plane-opensearch` (was `plane-opensearch-creds`), as on GCP.
- `rabbitmq_port` is left to the chart's default (5672) instead of being set in the values.
- With Plane AI on, the module turns on its indexing (`env.pi_envs.celery.vector_sync_enabled` and
  `workspace_plan_sync_enabled`, off in the chart), so pi embeds workspace data; the sync intervals stay the chart's,
  and `plane_values` can still override both.
