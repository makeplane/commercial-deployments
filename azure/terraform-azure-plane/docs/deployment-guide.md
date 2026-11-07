# Deploying Plane on Azure

> **Stub.** Sections to write, following `aws/terraform-aws-plane/docs/deployment-guide.md`. Content comes after the
> first apply in a real subscription (plan phase 2) and once Plane's Azure Blob support ships.

## Contents

1. **What gets deployed**: architecture diagram (resource group, VNet, AKS, PostgreSQL, Managed Redis, Key Vault, Blob,
   static IPs; in-cluster RabbitMQ and OpenSearch), cost estimate.
2. **Before you start**
   - Tools: Terraform ≥ 1.10, Azure CLI, kubelogin, kubectl, Helm (path B).
   - Subscription: roles (Owner, or Contributor + User Access Administrator), resource providers, quotas (DDSv5,
     PostgreSQL vCores, public IPs), region checklist (zones, Managed Redis, ZR HA, Premium ZRS), Azure Policy.
   - Domain and DNS (A and MX records), Plane licence.
3. **Choose how traffic reaches Plane**: paths A.1 / A.2 / B; importing a certificate into Key Vault (PEM or PFX,
   RBAC vault, the versionless resource ID).
4. **Set up Terraform state**: storage account with Entra ID auth (`use_azuread_auth`), versioning, soft delete,
   Storage Blob Data Contributor for the deployer.
5. **Configure**: `terraform.tfvars`, `backend.hcl`, `api_server_authorized_ip_ranges`.
6. **Deploy**: `az login`, `terraform init` / `apply`, timings, what to watch (`kubectl get pods -n plane`).
7. **Create the DNS records**: `terraform output dns_records` (A for `domain`, A + MX for `smtp_domain`).
8. **Finish the ingress setup**: A.1 (certificate issuance), A.2, B (routes for Traefik / NGINX / Application Gateway
   for Containers; destroy order for your own load balancers).
9. **Sign in and activate your licence**.
10. **Day-2 operations**: kubectl access (`configure_kubectl`), scaling, upgrades (Plane, chart, AKS), certificate
    renewal, rotating the Redis access key and the RabbitMQ and OpenSearch passwords (README, "Things to know"),
    backups (PostgreSQL PITR; RabbitMQ and OpenSearch disk snapshots; Blob versioning and soft delete).
11. **Removing the installation**: delete locks off (`postgres` / `storage` `deletion_protection`), destroy, Key Vault
    soft delete and purge protection, leftover disks.
12. **Troubleshooting**: Azure RBAC propagation (403 from Helm), External Secrets Workload Identity, `PublicIPAddressInUse`
    on destroy, Let's Encrypt HTTP-01, Key Vault firewall, Blob access from Plane.
