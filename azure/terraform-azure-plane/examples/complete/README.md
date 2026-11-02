# Complete example

An empty Azure subscription (or an empty resource group) to a running Plane on AKS. **`terraform.tfvars` is the one
place to configure it:** this example declares every module input under the same name and passes it straight through,
and anything you don't set keeps the module's default.

> Needs Plane's Azure Blob support and the matching chart release (module README, "Requires").

```bash
az login                                       # Helm authenticates through kubelogin with this login
cp terraform.tfvars.example terraform.tfvars   # set name, domain and location, pick a path, uncomment anything else
cp backend.hcl.example backend.hcl             # set the state storage account: state holds generated secrets
terraform init -backend-config=backend.hcl
terraform apply                                # about 40-70 minutes on a fresh install
terraform output dns_records                   # create these DNS records (the module creates none)
```

## Pick a path

```
Traefik installed by the module? ── no (your own controller) ─────────────────► PATH B
          │ yes
Certificates?
  ├─ Let's Encrypt (acme_email) ──────────────────────────► PATH A, A.1
  ├─ Your own, in Key Vault (certificate IDs) ────────────► PATH A, A.2
  └─ Other (Secret by hand, your cert-manager, App GW) ───► PATH B
```

| | Set in `terraform.tfvars` | After the apply |
|---|---|---|
| **A.1** Let's Encrypt | `ingress = { mode = "automated" }`, `acme_email` (optional: `email.certificate_secret_id`) | Create the DNS records (`terraform output dns_records`); the web certificate is issued once the record exists. Plane must be public on port 80. |
| **A.2** Your certificates | `ingress = { mode = "automated", tls_certificate_secret_id = … }` (optional: `email.certificate_secret_id`) | Create the DNS records |
| **B** Bring your own | Nothing (default) | Install your ingress controller, apply Plane's routes, add your certificate, create the DNS records |

Without an email certificate, the email service uses a self-signed one (fine for receiving mail).

`terraform.tfvars.example` shows every other setting with its default. For objects, set only the fields you change,
e.g. `node_pool = { max_count = 6 }`. The provider block sets the Key Vault `features` so a destroy leaves the
purge-protected vault soft-deleted instead of failing.
