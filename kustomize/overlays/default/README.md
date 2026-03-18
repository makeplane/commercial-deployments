# overlay: default

The default self-contained deployment. Deploys Plane to the `plane-default` namespace with **all local infrastructure** (postgres, redis, rabbitmq, minio) bundled in-cluster and `storageClassName: gp2` on every database PVC. No external services required — a complete stack out of the box.

---

## Quick start

```bash
# 1. Copy and fill in the config files
cp vars.yaml.example vars.yaml
cp secrets-vars.yaml.example secrets-vars.yaml

# 2. Edit vars.yaml — set APP_DOMAIN, WEB_URL, CORS_ALLOWED_ORIGINS
# 3. Edit secrets-vars.yaml — set SECRET_KEY, AES_SECRET_KEY, LIVE_SERVER_SECRET_KEY
#    (generate with: openssl rand -hex 32)

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
| `postgres` | enabled | In-cluster PostgreSQL |
| `redis` | enabled | In-cluster Redis (Valkey) |
| `rabbitmq` | enabled | In-cluster RabbitMQ |
| `minio` | enabled | In-cluster MinIO object storage |
| `nonroot-security-context` | disabled | Uncomment to harden workloads |
| `custom-ca` | disabled | Uncomment + add PEM to enable custom CA |
| `opensearch-external-auth` | disabled | Only needed for external OpenSearch with auth |

To toggle a component, comment or uncomment its line in `kustomization.yaml`.

---

## StorageClass

All four local DB StatefulSets (`plane-postgres`, `plane-redis`, `plane-rabbitmq`, `plane-minio`) and the monitor StatefulSet have their PVCs pinned to `storageClassName: gp2` via inline strategic-merge patches in `kustomization.yaml`. To use a different storage class, edit `MONITOR_STORAGE_CLASS` in `vars.yaml` and update the four patches accordingly.

---

## Validation

```bash
# Build and inspect without applying
kubectl kustomize .

# Verify namespace on all resources
kubectl kustomize . | grep "namespace:"

# Verify storageClassName on DB PVCs
kubectl kustomize . | grep -A5 "volumeClaimTemplates" | grep "storageClassName"
```
