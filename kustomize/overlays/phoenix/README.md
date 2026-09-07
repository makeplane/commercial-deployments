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
| `argus` | enabled | Content security / compliance scanning. Requires 7 new config keys — see [Upgrade note](#upgrade-note-argus-config-keys) below. Listed **before** `nonroot-security-context` so the workload is patched to run non-root. |
| `static-db-url` | disabled | Not needed with IRSA; enable for static DATABASE_URL |
| `s3-static-credentials` | disabled | Not needed with IRSA; enable for static AWS keys |
| `opensearch-external-auth` | disabled | Enable for external OpenSearch with auth |
| `postgres` | disabled | Uncomment to deploy in-cluster PostgreSQL |
| `redis` | disabled | Uncomment to deploy in-cluster Redis |
| `rabbitmq` | disabled | Uncomment to deploy in-cluster RabbitMQ |
| `minio` | disabled | Uncomment to deploy in-cluster MinIO |

To toggle a component, comment or uncomment its line in `kustomization.yaml`.

---

## Upgrade note: argus config keys

The `argus` component is enabled in this overlay and introduces **seven new
required keys**. `vars.yaml` and `secrets-vars.yaml` are gitignored (per-operator
files), so pulling this change does not add them for you. They are Kustomize
*replacement sources*, which means a missing key fails the **entire overlay
render** — not just the argus resources:

```
Error: accumulating components: accumulateDirectory: "recursed accumulation of
path '.../components/argus': fieldPath `stringData.ARGUS_DATABASE_URL` is
missing for replacement source Secret ... /overlay-secret-vars"
```

Fix by copying the new keys from the examples into your local files:

| File | New required keys |
|------|-------------------|
| `secrets-vars.yaml` | `ARGUS_DATABASE_URL`, `ARGUS_CONTENT_DATABASE_URL`, `ARGUS_FINGERPRINT_SECRET`, `ARGUS_INTERNAL_SECRET`, `ARGUS_FEATURE_FLAG_SERVER_AUTH_TOKEN` |
| `vars.yaml` | `ARGUS_TRUSTED_PROXIES`, `ARGUS_METRICS_ADDR` |

```bash
# see exactly what your local files are missing
diff <(grep -oE '^  [A-Z_]+:' vars.yaml.example)         <(grep -oE '^  [A-Z_]+:' vars.yaml)
diff <(grep -oE '^  [A-Z_]+:' secrets-vars.yaml.example) <(grep -oE '^  [A-Z_]+:' secrets-vars.yaml)
```

Then, before applying:

- **`ARGUS_FINGERPRINT_SECRET`** — generate a real one with
  `openssl rand -hex 32`. The example ships empty so startup fails closed; argus
  accepts plausible-looking placeholders, and rotating this key later
  invalidates every stored fingerprint and triage decision.
- **`ARGUS_DATABASE_URL`** — must point at the **same** database the app uses
  (argus reads Plane's content tables read-only and creates its own `argus`
  schema there). Argus has no Secrets Manager support, so on an RDS password
  rotation every other workload follows `RDS_SECRET_ARN` while argus keeps this
  static DSN and CrashLoops until you update it by hand.
- **`ARGUS_TRUSTED_PROXIES`** — while empty, argus ignores `X-Forwarded-For` and
  every audit event records the ingress pod's IP instead of the end user's. Set
  it to your ingress controller's pod CIDR if the audit trail matters.
- **Traefik users** — the `/argus` route is index 13 in
  `components/ingress-traefik/ingress-route.yaml`; the matching Host patch is
  already in this overlay's `kustomization.yaml`.

To opt out instead, comment out `../../components/argus` in `kustomization.yaml`
(as `default` and `managed` do) and none of the above applies.

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
