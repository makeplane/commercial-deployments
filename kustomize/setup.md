# How to Deploy Plane with Kustomize

This guide walks you through deploying Plane Commercial on Kubernetes using the Kustomize overlays in this repository. For architecture details, component reference, and production tuning, see [README.md](README.md).

---

## Prerequisites

- **Kubernetes cluster** (v1.31+) with `kubectl` configured
- **kubectl** with Kustomize support (`kubectl kustomize --help` works)
- **Image pull access** to `artifacts.plane.so` (Plane Commercial images). If your cluster needs pull secrets, create them in the target namespace and reference them in your overlay
- **StorageClass** for PersistentVolumeClaims (required if you use local infrastructure components such as Postgres, Redis, MinIO)
- **Ingress controller** (optional but recommended for external access): either install one yourself or use the provided [ingress-nginx](#step-5-optional-choose-an-ingress-controller) or [AWS Load Balancer Controller](#step-5-optional-choose-an-ingress-controller) components

---

## Step 1: Copy the example overlay

Create a new overlay for your environment (e.g. dev, staging, production):

```bash
cd kustomize/overlays
cp -r example my-env
cd my-env
```

All following steps refer to files under `overlays/my-env/`. Use your overlay name instead of `my-env` if different.

---

## Step 2: Configure non-sensitive settings (`vars.yaml`)

Copy the example and edit:

```bash
cp vars.yaml.example vars.yaml
# Edit with your domain, URLs, and ingress class
```

Set at least:

| Key | Description | Example |
|-----|-------------|---------|
| `APP_VERSION` | Must match image tags in `kustomization.yaml` | `v2.3.3` |
| `APP_DOMAIN` | Domain without protocol | `plane.mycompany.com` |
| `WEB_URL` | Full app URL with protocol | `https://plane.mycompany.com` |
| `CORS_ALLOWED_ORIGINS` | Comma-separated origins | `https://plane.mycompany.com` |
| `INGRESS_CLASS` | Ingress controller class | `nginx` or `alb` |
| `IS_AIRGAPPED` | `1` for air-gapped, else `0` | `0` |

`vars.yaml` is a ConfigMap marked as local-config; its values are used by Kustomize replacements and are not applied as a standalone resource. It is safe to commit (no secrets).

---

## Step 3: Configure secrets (`secrets-vars.yaml`)

Copy the example and fill in real values. **Do not commit this file** (it is in `.gitignore`):

```bash
cp secrets-vars.yaml.example secrets-vars.yaml
# Edit with your credentials and connection strings
```

You must set:

- **Infrastructure (if not using local components):** `DATABASE_URL`, `REDIS_URL`, `REDIS_URL_LIVE`, `AMQP_URL`, OpenSearch vars, and S3/MinIO vars (`AWS_*`).
- **Application secrets:** `SECRET_KEY`, `AES_SECRET_KEY`, `LIVE_SERVER_SECRET_KEY` — generate with e.g. `openssl rand -hex 32` and never use defaults in production.

If you **include** local infrastructure components (Postgres, Redis, RabbitMQ, MinIO, OpenSearch) in your overlay, their component patches will override the corresponding URLs in the generated manifests; you can still set fallbacks in `secrets-vars.yaml` for consistency.

---

## Step 4: Choose infrastructure: local components or external services

Open `overlays/my-env/kustomization.yaml` and under `components:` either:

**Option A – Local infrastructure (dev / self‑hosted)**  
Uncomment the infrastructure components so Plane runs Postgres, Redis, RabbitMQ, MinIO, and OpenSearch in the cluster:

```yaml
components:
  - ../../components/silo
  - ../../components/email-service
  # Uncomment for local infrastructure:
  - ../../components/postgres
  - ../../components/redis
  - ../../components/rabbitmq
  - ../../components/minio
  - ../../components/opensearch
```

**Option B – External/managed services (typical for production)**  
Leave those components commented and configure all connection strings and credentials in `secrets-vars.yaml` (e.g. RDS, ElastiCache, Amazon MQ, S3, OpenSearch).

You can mix: e.g. local Postgres + external Redis; ensure the right URLs are set in `secrets-vars.yaml` for any service not provided by a component.

---

## Step 5: (Optional) Choose an ingress controller

The base Ingress is controller-agnostic. To install an ingress controller via this repo, **pick one** of the following and set the matching `INGRESS_CLASS` in `vars.yaml`.

**Option 1 – NGINX Ingress**  
In `kustomization.yaml` under `components:` add:

```yaml
  - ../../components/ingress-nginx
```

In `vars.yaml` set `INGRESS_CLASS: "nginx"`.

**Option 2 – AWS Load Balancer Controller (EKS)**  
In `kustomization.yaml` under `components:` add:

```yaml
  - ../../components/aws-load-balancer-controller
```

In `vars.yaml` set `INGRESS_CLASS: "alb"` and **`AWS_LB_CONTROLLER_ROLE_ARN`** to your IAM role ARN (e.g. `arn:aws:iam::123456789012:role/my-cluster-aws-lb-controller`). The overlay replacement will inject this into the controller’s ServiceAccount—do not edit files inside `components/aws-load-balancer-controller/`. Complete the IAM and IRSA setup (OIDC, IAM policy, role) as in [AWS_load_balancer_setup.md](AWS_load_balancer_setup.md), and set `clusterName`, `region`, and `vpcId` only in the component’s `values.yaml` if needed.

If you use either component, you must **build with Helm enabled** when deploying (Step 6).

---

## Step 6: Deploy

From the repository root:

**If you did not add an ingress controller component** (Step 5):

```bash
kubectl apply -k kustomize/overlays/my-env
```

**If you added the ingress-nginx or aws-load-balancer-controller component** (Step 5):

```bash
kubectl kustomize kustomize/overlays/my-env --enable-helm | kubectl apply -f -
```

Or with standalone Kustomize:

```bash
kustomize build kustomize/overlays/my-env --enable-helm | kubectl apply -f -
```

To preview manifests without applying:

```bash
kubectl kustomize kustomize/overlays/my-env
# or with Helm components:
kubectl kustomize kustomize/overlays/my-env --enable-helm
```

The overlay’s `namespace` (e.g. `plane-ns` in the example) is where all resources are deployed.

---

## Step 7: Verify and access

- Check that pods are running in the overlay namespace:

  ```bash
  kubectl get pods -n plane-ns
  kubectl get ingress -n plane-ns
  ```

- Wait for the migrator job to complete and for deployments to be ready:

  ```bash
  kubectl rollout status -n plane-ns deployment/plane-api-wl
  ```

- Access Plane:
  - **Via Ingress:** Use the host and paths configured on the Ingress (e.g. `https://plane.mycompany.com` if you set `APP_DOMAIN` and have DNS and TLS in place).
  - **Via port-forward (no Ingress):**  
    `kubectl port-forward -n plane-ns svc/plane-web 3000:3000`  
    Then open `http://localhost:3000`.

---

## Summary checklist

1. Copy `overlays/example` to `overlays/my-env`.
2. Create and edit `vars.yaml` (domain, `WEB_URL`, `INGRESS_CLASS`, etc.).
3. Create and edit `secrets-vars.yaml` (DB, Redis, AMQP, OpenSearch, S3, app secrets).
4. In `kustomization.yaml`, enable the infrastructure components you want (or rely on external services and secrets only).
5. Optionally add one ingress controller component and set the matching `INGRESS_CLASS` in `vars.yaml`.
6. Deploy with `kubectl apply -k` (or with `--enable-helm` if an ingress component is used).
7. Verify pods and Ingress, then open the app in the browser or via port-forward.

For more detail on components, replacements, production sizing, and security, see [README.md](README.md). For AWS Load Balancer Controller IAM and IRSA, see [AWS_load_balancer_setup.md](AWS_load_balancer_setup.md).
