# overlay: example

Full-featured reference overlay targeting the `plane-ns` namespace. Enables EKS IRSA, Pi service, nonroot security context, and custom CA — intended as a starting point for AWS EKS production deployments or as a reference when building a custom overlay.

This overlay is **not meant to be applied as-is**. Copy it and adapt it to your environment.

---

## Quick start

```bash
# 1. Copy and fill in the config files
cp vars.yaml.example vars.yaml
cp secrets-vars.yaml.example secrets-vars.yaml

# 2. Edit vars.yaml — set APP_DOMAIN, ARNs, and other AWS-specific fields
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
| `eks-irsa-plane-serviceaccount` | enabled | IRSA role annotation on ServiceAccount |
| `ingress-nginx` | enabled | Swap for `aws-load-balancer-controller` if needed |
| `pi-service` | enabled | AI/Intelligence features |
| `runner` | enabled | Node automation runner |
| `nonroot-security-context` | enabled | Non-root security context on all workloads |
| `custom-ca` | enabled | Custom CA cert — add PEM to `../../components/custom-ca/customCA.crt` |
| `static-db-url` | disabled | Not needed with IRSA; enable for static DATABASE_URL |
| `s3-static-credentials` | disabled | Not needed with IRSA; enable for static AWS keys |
| `opensearch-external-auth` | disabled | Enable for external OpenSearch with auth |
| `postgres` | disabled | Uncomment to deploy in-cluster PostgreSQL |
| `redis` | disabled | Uncomment to deploy in-cluster Redis |
| `rabbitmq` | disabled | Uncomment to deploy in-cluster RabbitMQ |
| `minio` | disabled | Uncomment to deploy in-cluster MinIO |

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
