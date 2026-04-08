# Custom CA Certificate Support

## What Changed

A new optional Kustomize **component** was added at `kustomize/components/custom-ca/` that mounts a custom CA certificate into every Plane workload container, builds a combined CA bundle at pod startup, and automatically configures the relevant runtime env vars.

**Files added:**

| File | Purpose |
|------|---------|
| `kustomize/components/custom-ca/kustomization.yaml` | Component definition — creates two ConfigMaps and applies JSON patches to all workloads |
| `kustomize/components/custom-ca/customCA.crt.example` | Example PEM certificate (replace with your actual CA cert) |
| `kustomize/components/custom-ca/patches/add-ca-volume.json` | Sets the `volumes` array (for workloads with no existing volumes) |
| `kustomize/components/custom-ca/patches/append-ca-volume.json` | Appends to an existing `volumes` array |
| `kustomize/components/custom-ca/patches/add-ca-volumemount.json` | Sets the `volumeMounts` array (for containers with no existing mounts) |
| `kustomize/components/custom-ca/patches/append-ca-volumemount.json` | Appends to an existing `volumeMounts` array |
| `kustomize/components/custom-ca/patches/add-ca-envfrom.json` | Sets the `envFrom` array (for containers with no existing envFrom) |
| `kustomize/components/custom-ca/patches/append-ca-envfrom.json` | Appends to an existing `envFrom` array |
| `kustomize/components/custom-ca/patches/append-combined-ca-volume.json` | Appends the `combined-ca` emptyDir volume used by the init container |
| `kustomize/components/custom-ca/patches/append-combined-ca-volumemount.json` | Appends the `/combined-ca` mount to every container |
| `kustomize/components/custom-ca/patches/add-ca-init-container.json` | Adds the init container that builds the combined CA bundle |

**What the component does when enabled:**

- Creates a `plane-custom-ca` ConfigMap from your `customCA.crt` file and mounts it into every container at `/etc/ssl/certs/customCA.crt`.
- Adds an **init container** to every pod that concatenates the system CA bundle with your custom CA into `/combined-ca/ca-bundle.crt`. This ensures standard TLS endpoints (e.g. AWS APIs) remain trusted alongside your internal services.
- The init container prefers the system CA bundle from `/etc/ssl/certs/ca-certificates.crt`; if it is not present, it tries `/etc/ssl/cert.pem`. If neither system path exists, it falls back to using only the mounted custom CA at `/custom-ca/customCA.crt`.
- Creates a `plane-custom-ca-env` ConfigMap and injects the following env vars into every container:
  - `REQUESTS_CA_BUNDLE=/combined-ca/ca-bundle.crt` — used by Python / `requests`
  - `AWS_CA_BUNDLE=/combined-ca/ca-bundle.crt` — used by Python `boto3` / `botocore`
  - `NODE_EXTRA_CA_CERTS=/etc/ssl/certs/customCA.crt` — used by Node.js (appends to the built-in bundle, does not replace it)

> **Init container image:** each pod's init container uses the same image as its main container — no additional images to procure or scan. The `images` transformer in your overlay automatically applies the correct pinned tag to both.

> **Conditional:** init containers are only present when this component is enabled. Base deployments have no `initContainers` defined, so overlays that omit `custom-ca` are unaffected.

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

All Plane workload containers (Deployments, Jobs, StatefulSets) will have the CA cert mounted, the combined bundle built at startup, and the env vars set automatically.
