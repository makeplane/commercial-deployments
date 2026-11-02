# Deploying Plane on Google Cloud

> **Stub.** The sections below follow the AWS guide (`aws/terraform-aws-plane/docs/deployment-guide.md`). Each lists
> what to write; fill them in after the first end-to-end apply on a real GCP project.

## Contents

1. What gets deployed
2. Before you start
3. Choose how traffic reaches Plane
4. Set up Terraform state
5. Configure
6. Deploy
7. Create the DNS records
8. Finish the ingress setup
9. Sign in and activate your licence
10. Day-2 operations
11. Removing the installation
12. Troubleshooting

## 1. What gets deployed

To write: the architecture (VPC, Cloud NAT, private services access, GKE, Cloud SQL, Memorystore, GCS, Secret Manager,
in-cluster RabbitMQ and OpenSearch, the reserved static IPs) and a cost estimate per month.

## 2. Before you start

To write:
- Tools: Terraform ≥ 1.10, gcloud, `gke-gcloud-auth-plugin`, kubectl, helm, jq.
- GCP project: dedicated, billing linked, Owner (or the least-privilege role list), quotas (N2D CPUs, external IPs,
  SSD), organisation policies to check (load balancer types, VPC peering, resource locations, CMEK).
- Domain and DNS: who creates the A and MX records.
- Plane licence.

## 3. Choose how traffic reaches Plane

To write: paths A.1, A.2 and B (as the module README), and "Storing a certificate in Secret Manager"
(`gcloud secrets create … --data-file`, JSON keys `tls.crt`/`tls.key`, same project, regional replication).

## 4. Set up Terraform state

To write: a versioned, uniform-access GCS bucket (`gcloud storage buckets create … --uniform-bucket-level-access`,
versioning on), `backend.hcl`, access limited to the deployers (state holds generated secrets).

## 5. Configure

To write: `terraform.tfvars` from the example (project_id, region, name, domain, path, `master_authorized_networks`).

## 6. Deploy

To write: `gcloud auth application-default login`, `terraform init -backend-config=backend.hcl`, `terraform apply`,
expected duration, what to watch (`kubectl -n plane get pods`, ExternalSecrets Ready).

## 7. Create the DNS records

To write: `terraform output dns_records`: A for domain (path A), A + MX for smtp_domain.

## 8. Finish the ingress setup

To write: A.1 (certificate issued after DNS), A.2 (nothing more), B (routes from the chart, certificate, DNS).

## 9. Sign in and activate your licence

To write: setup wizard, licence activation, `/god-mode` settings.

## 10. Day-2 operations

To write: upgrading Plane and the chart, node pool sizing, Cloud SQL backups and PITR restore, disk snapshots for the
in-cluster RabbitMQ and OpenSearch, renewing your certificates, Redis TLS opt-in.

## 11. Removing the installation

To write: `postgres = { deletion_protection = false }` and `bucket_force_destroy`, apply, destroy; path B: remove your
ingress first; delete the orphaned persistent disks (`gcloud compute disks list --filter="name~^pvc-"`); what is left
(APIs enabled, Cloud SQL backups per retention).

## 12. Troubleshooting

To write: Workload Identity not ready yet (pods retry), ExternalSecret errors (IAM on the secret), load balancer IP
pending (reserved address in use or annotation), OpenSearch PVC Pending (storage class), Cloud SQL TLS errors, quota
errors.
