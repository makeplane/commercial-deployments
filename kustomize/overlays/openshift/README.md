# overlay: openshift

Deploys Plane to the `plane-openshift` namespace under OpenShift's default
**`restricted-v2`** SCC, with **native Routes** instead of an Ingress and **no
bundled datastores**.

Start from this overlay for any OpenShift cluster. Copying `default` and toggling
components does not work: `default` pins `runAsUser: 1000` and ships the
in-cluster datastores, and both are rejected on OpenShift.

---

## What OpenShift changes

`restricted-v2` ignores the image's `USER`, assigns an **arbitrary UID** from the
namespace's range, and places the process in **group 0**. It also validates the
pod's own request with `MustRunAsRange`, so a manifest asking for a *specific*
`runAsUser`/`runAsGroup`/`fsGroup` outside that range is **rejected at
admission** — nothing schedules, and the error comes from admission rather than
the workload.

Three consequences, all handled by this overlay:

| | `default` overlay | this overlay |
|---|---|---|
| Hardening | `nonroot-security-context` (pins uid 1000) | `openshift-security-context` (no UID named) |
| Ingress | base nginx `Ingress` | `ingress-openshift` → one Route per path |
| Datastores | postgres/redis/rabbitmq/minio/opensearch in-cluster | **external only** |

---

## Prerequisites

- **Images that support an arbitrary UID.** They must grant group 0 write access
  to the paths they write at runtime. Older images crash — nginx exits with
  `mkdir() "/var/cache/nginx/client_temp" failed (13: Permission denied)` and
  celery beat cannot create its schedule DB.
- **External PostgreSQL, Redis, RabbitMQ, S3 and (optionally) OpenSearch.** The
  bundled ones are third-party images with baked-in UID and data-directory
  ownership; they cannot run under an arbitrary UID.
- A **storage class** for the monitor PVC — check `oc get storageclass` and set
  `MONITOR_STORAGE_CLASS` accordingly (`gp3-csi` on ROSA, `thin-csi` on vSphere,
  `ocs-storagecluster-ceph-rbd` on ODF).

---

## Quick start

```bash
# 1. Copy and fill in the config files
cp vars.yaml.example vars.yaml
cp secrets-vars.yaml.example secrets-vars.yaml

# 2. Edit vars.yaml — set APP_DOMAIN, WEB_URL, CORS_ALLOWED_ORIGINS,
#    MONITOR_STORAGE_CLASS
# 3. Edit secrets-vars.yaml — point every connection string at your EXTERNAL
#    services, then set SECRET_KEY, AES_SECRET_KEY, LIVE_SERVER_SECRET_KEY
#    (generate with: openssl rand -hex 32)

# 4. Create the project
oc new-project plane-openshift

# 5. Validate before applying — this is where an SCC rejection would surface
oc kustomize . | oc apply --dry-run=server -f -

# 6. Apply
oc kustomize . | oc apply -f -
```

Confirm the SCC that was actually applied, and the UID it handed out:

```bash
oc get pods -o custom-columns=\
NAME:.metadata.name,SCC:.metadata.annotations.openshift\\.io/scc,UID:.spec.securityContext.runAsUser
```

---

## Enabled components

| Component | Status | Notes |
|-----------|--------|-------|
| `openshift-security-context` | **enabled** | Hardening without a pinned UID. Never enable `nonroot-security-context` here. |
| `ingress-openshift` | **enabled** | Removes the base Ingress, adds 11 Routes with `haproxy.router.openshift.io/timeout: 300s`. |
| `email-service` | enabled | Transactional email |
| `static-db-url` | enabled | Injects `DATABASE_URL` into **both** `plane-app-secrets` and `plane-silo-secrets`. Silo gets it from nowhere else. |
| `s3-static-credentials` | enabled | Injects the AWS keys. Drop it only if the ServiceAccount assumes a cloud role — and then omit the key fields entirely rather than blanking them, since an empty `AWS_ACCESS_KEY_ID` shadows the role. |
| `runner` | enabled | Node automation runner |
| `external-api` | enabled | Cloud-entrypoint API workload |
| `worker-importers` | enabled | `celery.importer` queue |
| `webhook-consumer` | enabled | RabbitMQ consumer for webhook delivery |
| `agent-consumer` | enabled | RabbitMQ consumer for agent events |
| `custom-ca` | disabled | Uncomment to mount a private CA |
| `opensearch-external-auth` | disabled | Uncomment for OpenSearch basic auth |
| `otel-observability` | disabled | See `overlays/phoenix` for a worked example |
| `postgres` / `redis` / `rabbitmq` / `minio` / `opensearch` | **omitted** | Cannot run under an arbitrary UID — use external services |
| `ingress-nginx` / `ingress-traefik` / `aws-load-balancer-controller` | **omitted** | Would conflict with the Routes |

---

## Known gaps

- **No request-body limit.** OpenShift Routes cannot cap request bodies the way
  Traefik's `plane-body-limit` middleware does, so `FILE_SIZE_LIMIT` in
  `secrets-vars.yaml` is the only upload guard.
- **No path rewriting.** A path needing a prefix strip (e.g. the `draw-io`
  component) requires `haproxy.router.openshift.io/rewrite-target` on that Route.
  `draw-io` is therefore not enabled here.
- **TLS** is the Ingress Operator's wildcard certificate, via `termination: edge`.
  To serve your own, add `spec.tls.externalCertificate.name` to the Routes
  (OpenShift 4.16+, and the router needs a RoleBinding to read that Secret).

---

## Upgrading an existing install onto this overlay

Moving from the pinned-uid-1000 posture needs **no data migration**. kubelet
re-applies `fsGroup` to PVC contents on mount, so data written by the old
deployment stays readable and writable by the newly assigned UID. This was
verified end to end against the monitor PVC, which is the only stateful
first-party workload.
