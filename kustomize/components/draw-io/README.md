# draw.io component

Self-hosted [draw.io](https://www.drawio.com/) (diagram editor) for Plane.

This component ships a `Deployment` + ClusterIP `Service` only — reachable
in-cluster at `plane-draw-io:8080`. It deliberately adds **no public ingress**,
because the route depends on which ingress controller the overlay uses. Wire it
up at the overlay/infra layer using one of the recipes below.

> **Image versioning:** `makeplane/drawio` is versioned independently of
> `APP_VERSION`. The tag is driven by `DRAWIO_VERSION` in each overlay's
> `vars.yaml` — bump it there, not in `deployment.yaml`.

## Hosting draw.io on a `/drawio` subpath

The `makeplane/drawio` image serves its webapp at `/` and references **all assets
relatively** (`js/`, `styles/`, `images/`, `mxBasePath`). Exposing it on a
subpath therefore needs exactly two things from the ingress layer:

1. **Strip the `/drawio` prefix** before forwarding, so the container sees `/`.
2. **Redirect the bare `/drawio` → `/drawio/`** (trailing slash). Relative assets
   resolve against the page URL; without the trailing slash the browser requests
   `/js/...` at the domain root and 404s.

Always share the link **with** the trailing slash (`https://<host>/drawio/`); the
redirect covers anyone who drops it.

### Traefik (`ingress-traefik` component)

Already wired up: the `ingress-traefik` component defines `drawio-stripprefix`
and `drawio-redirect-slash` middlewares plus a `PathPrefix(`/drawio`)` route on
`plane-ingress-route`. Enable the `draw-io` and `ingress-traefik` components in
your overlay, then patch the route's `Host(...)` to your domain (see the
`phoenix` overlay's `patches:` block for the index-based example).

### nginx (`ingress-nginx` component)

The base `plane-ingress` forwards paths as-is, so draw.io needs its **own**
Ingress objects — `rewrite-target` is a per-Ingress annotation and must not leak
onto the main Plane routes. Apply the following alongside your Plane deployment,
replacing **both** `<domain.com>` placeholders (the redirect URL is absolute):

```yaml
# 1) Strip the /drawio prefix and forward to draw.io (which serves at "/").
#    /drawio/js/main.js -> /js/main.js ,  /drawio/ -> /
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: drawio
  namespace: plane
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
spec:
  ingressClassName: nginx
  rules:
    - host: <domain.com>
      http:
        paths:
          - path: /drawio(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: plane-draw-io
                port:
                  number: 8080
---
# 2) Redirect the bare /drawio -> /drawio/ so relative assets resolve.
#    Exact match, so deeper /drawio/... requests pass through to Ingress #1.
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: drawio-redirect-slash
  namespace: plane
  annotations:
    nginx.ingress.kubernetes.io/permanent-redirect: https://<domain.com>/drawio/
spec:
  ingressClassName: nginx
  rules:
    - host: <domain.com>
      http:
        paths:
          - path: /drawio
            pathType: Exact
            backend:
              service:
                name: plane-draw-io
                port:
                  number: 8080
```

Notes:

- The `plane-draw-io` Service (port 8080) must be deployed in the same namespace
  (enable the `draw-io` component).
- `rewrite-target` / `use-regex` are standard annotations and always available.
  This intentionally avoids `configuration-snippet`, which is disabled by default
  in ingress-nginx ≥ v1.9.
- `proxy-body-size: 50m` mirrors the standalone draw.io recipe; lower it if your
  controller enforces a stricter default.

#### Ingress ↔ Traefik annotation mapping

| Job                      | Traefik                       | nginx-ingress                                   |
| ------------------------ | ----------------------------- | ----------------------------------------------- |
| Strip `/drawio` prefix   | `stripPrefix` middleware      | `rewrite-target: /$2` + regex path + `use-regex`|
| `/drawio` → `/drawio/`   | `redirectRegex` middleware    | `permanent-redirect` on `pathType: Exact` route |
| Request body limit       | `buffering.maxRequestBodyBytes` | `proxy-body-size` annotation                  |
