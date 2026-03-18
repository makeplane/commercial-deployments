# overlay: managed

Deploys Plane to the `plane-managed` namespace and connects to **external managed services** via static credentials — AWS RDS (Postgres), ElastiCache (Redis), Amazon MQ (AMQP), S3, and Amazon OpenSearch Service. No local infrastructure components are deployed; all services are expected to exist outside the cluster.

---

## Quick start

```bash
# 1. Copy and fill in the config files
cp vars.yaml.example vars.yaml
cp secrets-vars.yaml.example secrets-vars.yaml

# 2. Edit vars.yaml — set APP_DOMAIN, WEB_URL, CORS_ALLOWED_ORIGINS
# 3. Edit secrets-vars.yaml — set connection strings and secret keys
#    (generate keys with: openssl rand -hex 32)

# 4. Validate before applying
kubectl kustomize . | kubectl apply --dry-run=client -f -

# 5. Apply
kubectl kustomize . | kubectl apply -f -
```

---

## Enabled components

| Component | Status | Notes |
|-----------|--------|-------|
| `email-service` | enabled | Transactional email |
| `ingress-nginx` | enabled | Swap for `aws-load-balancer-controller` if needed |
| `static-db-url` | enabled | Injects `DATABASE_URL` from `secrets-vars.yaml` |
| `s3-static-credentials` | enabled | Injects AWS/MinIO keys from `secrets-vars.yaml` |
| `runner` | enabled | Node automation runner |
| `nonroot-security-context` | disabled | Uncomment to harden workloads |
| `custom-ca` | disabled | Uncomment + add PEM to enable custom CA |
| `opensearch-external-auth` | disabled | Uncomment when Amazon OpenSearch requires username/password auth |
| `eks-irsa-plane-serviceaccount` | disabled | Enable instead of static-db-url + s3-static-credentials when using EKS IAM roles |

To toggle a component, comment or uncomment its line in `kustomization.yaml`.

---

## Validation

```bash
# Build and inspect without applying
kubectl kustomize .

# Verify namespace on all resources
kubectl kustomize . | grep "namespace:"

# Dry-run apply to a cluster
kubectl kustomize . | kubectl apply --dry-run=client -f -
```
