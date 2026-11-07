# Changelog

## Unreleased

> **Not releasable yet.** Needs Plane's native Azure Blob storage support (api and silo) and the plane-enterprise
> chart release that renders it, plus chart 3.12.2 (bundled RabbitMQ reading `external_secrets.rabbitmq`). The Blob
> chart values follow the **agreed contract** (`modules/plane/main.tf`, "AZURE BLOB STORAGE"); the `plane_version`
> (`v4.0.1`) and `chart_version` (`3.12.2`) defaults are placeholders until those releases exist. See README, "Requires".

### Added
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
- Every Key Vault certificate ID you pass (`ingress.tls_certificate_secret_id`, `email.certificate_secret_id`) is checked
  at plan: a full, versionless resource ID in this subscription. `cluster_admin_object_ids` must be GUIDs.
- Plane AI (pi) on AKS, off by default: `enable_components.pi = true` runs it on the Blob container (Plane's Workload
  Identity) and the in-cluster OpenSearch, with chat and semantic search (`pi` input). OpenAI chat and Cohere embeddings
  (`cohere/embed-v4.0`) by default, or Anthropic chat (`pi.api_keys.chat_provider`) and another of Plane AI's Cohere or
  OpenAI embedding models. The search indexes' dimension (`OPENSEARCH_EMBEDDING_DIMENSION`) follows
  `pi.api_keys.embedding_model`, with pi on or off (1536 by default). Both keys are required, as secrets in one Key Vault
  of yours, by ID: External Secrets gets read on those secrets only and copies them into the env var Plane AI reads (the
  keys never pass through Terraform). pi needs `opensearch.enabled` and a `plane_version` whose Plane AI supports Azure
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
  tests (`tests/*.tftest.hcl`) for the edge paths, add-ons, the generated chart values and the data layer; CI workflow
  `terraform-azure-plane.yml` (fmt, validate, test, tflint, checkov, terraform-docs, example inputs).
