# external-secrets

Reads credentials from AWS Secrets Manager at runtime instead of carrying them in
`secrets-vars.yaml`.

## What it creates

| Object | Purpose |
| --- | --- |
| `ServiceAccount/plane-eso-sa` | The identity the store authenticates as (IRSA) |
| `SecretStore/plane-aws-secrets-manager` | Namespaced store, `auth.jwt` against that SA |
| `Secret/plane-app-keys-ext` | `SECRET_KEY`, `AES_SECRET_KEY`, `LIVE_SERVER_SECRET_KEY`, `PI_INTERNAL_SECRET` |
| `Secret/plane-mcp-oauth-ext` | `PLANE_OAUTH_PROVIDER_CLIENT_ID` / `_SECRET` |

## Why separate Secrets rather than filling `plane-app-secrets`

`plane-app-secrets` is rendered by kustomize and populated by replacements. An
ExternalSecret targeting it would be a **second writer**: kustomize reapplies the
committed value, ESO resyncs the remote one, and the two flap. A separate Secret
placed **last** in a workload's `envFrom` wins over the earlier entry without
either side contesting ownership — and it lets the committed values be emptied
rather than deleted, which matters because they are replacement sources and
deleting one fails the whole overlay render.

## Wiring it to workloads (do this in your overlay)

This component deliberately attaches nothing. Add to your overlay's
`kustomization.yaml`, listing only workloads that overlay actually has:

```yaml
patches:
  - target:
      kind: Deployment
      name: plane-(api|worker|beat-worker|silo|outbox-poller|automation-consumer)-wl
    patch: |
      - op: add
        path: /spec/template/spec/containers/0/envFrom/-
        value:
          secretRef:
            name: plane-app-keys-ext
```

`envFrom` must already exist on container 0 — it does on every workload that
consumes `plane-app-secrets`, but not on `plane-iframely-wl` or `plane-draw-io-wl`,
which need neither.

**Order is the mechanism.** Kubernetes resolves `envFrom` in order and later
entries win, so `plane-app-keys-ext` must be appended after `plane-app-secrets`.
`op: add` with `/-` does that.

## Rotation

ESO refreshes the Secret on `refreshInterval`, but `envFrom` is resolved at
**container start**, so a rotated value does not reach a running pod until it
restarts. Install Reloader (or restart by hand) if rotation needs to land
without a deploy.

## Prerequisites

1. External Secrets Operator in the cluster.
2. An IAM role for `ESO_ROLE_ARN` with a **web-identity** trust policy for the
   cluster's OIDC provider and subject
   `system:serviceaccount:<namespace>:plane-eso-sa`, plus
   `secretsmanager:GetSecretValue` on the ARNs (and `kms:Decrypt` for a CMK).
   It must be IRSA — ESO's `auth.jwt` is `AssumeRoleWithWebIdentity`, so a Pod
   Identity role is not interchangeable.
