# Custom CA Certificate Support

## What Changed

A new optional Kustomize **component** was added at `kustomize/components/custom-ca/` that mounts a custom CA certificate into every Plane workload container and automatically configures the relevant runtime env vars.

**Files added:**

| File | Purpose |
|------|---------|
| `kustomize/components/custom-ca/kustomization.yaml` | Component definition — creates two ConfigMaps and applies JSON patches to all workloads |
| `kustomize/components/custom-ca/customCA.crt.example` | Example PEM certificate (replace with your actual CA cert) |
| `kustomize/components/custom-ca/patches/` | JSON patch files for volumes, volumeMounts, and envFrom across all Deployment / Job / StatefulSet resources |

**What the component does when enabled:**

- Creates a `plane-custom-ca` ConfigMap from your `customCA.crt` file and mounts it into every container at `/etc/ssl/certs/customCA.crt`.
- Creates a `plane-custom-ca-env` ConfigMap and injects two env vars into every container:
  - `REQUESTS_CA_BUNDLE=/etc/ssl/certs/customCA.crt` — used by Python / `requests`
  - `NODE_EXTRA_CA_CERTS=/etc/ssl/certs/customCA.crt` — used by Node.js

The example overlay at `kustomize/overlays/example/kustomization.yaml` was updated with a commented-out reference to this component showing where to enable it.

---

## How to Use

### 1. Provide your CA certificate

Copy your CA certificate (PEM format) to:

```
kustomize/components/custom-ca/customCA.crt
```

The file must look like:

```
-----BEGIN CERTIFICATE-----
<base64-encoded certificate data>
-----END CERTIFICATE-----
```

> See `customCA.crt.example` for the expected format. Do **not** commit the real cert file if it is sensitive — add it to `.gitignore` or manage it via a secrets pipeline.

### 2. Enable the component in your overlay

In your overlay's `kustomization.yaml`, add `custom-ca` to the `components` list:

```yaml
components:
  - ../../components/custom-ca
```

**Example** (`kustomize/overlays/example/kustomization.yaml`):

```yaml
components:
  - ../../components/pi-service
  - ../../components/nonroot-security-context
  - ../../components/custom-ca   # <-- add this line
```

### 3. Deploy with Kustomize

```bash
# Preview the rendered manifests
kubectl kustomize kustomize/overlays/<your-overlay>/

# Apply to the cluster
kubectl apply -k kustomize/overlays/<your-overlay>/
```

All Plane workload containers (Deployments, Jobs, StatefulSets) will have the CA cert mounted and the env vars set automatically.
