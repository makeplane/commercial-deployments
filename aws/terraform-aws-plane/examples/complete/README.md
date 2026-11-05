# Complete example

An empty AWS account to a running Plane on EKS, or on one EC2 instance with Docker Compose
(`deployment_mode = "docker"`, see below). **`terraform.tfvars` is the one place to configure it:** this example
declares every module input under the same name and passes it straight through, and anything you don't set keeps the
module's default.

```bash
cp terraform.tfvars.example terraform.tfvars   # set name and domain, pick a path, uncomment anything else
cp backend.hcl.example backend.hcl             # set the state bucket: state holds generated secrets
terraform init -backend-config=backend.hcl
terraform apply                                # 45-75 minutes on a fresh install
terraform output dns_records                   # create these DNS records (the module creates none)
```

## Pick a path

```
Traefik installed by the module? ── no (your own controller) ─────────────────► PATH B
          │ yes
Certificates?
  ├─ Let's Encrypt (acme_email) ──────────────────────────► PATH A, A.1
  ├─ Your own, in Secrets Manager (ARNs) ─────────────────► PATH A, A.2
  └─ Other (Secret by hand, your cert-manager, ACM) ──────► PATH B
```

| | Set in `terraform.tfvars` | After the apply |
|---|---|---|
| **A.1** Let's Encrypt | `ingress = { mode = "automated" }`, `acme_email` (optional: `email.certificate_secret_arn`) | Create the DNS records (`terraform output dns_records`); the web certificate is issued once the record exists. Plane must be public on port 80. |
| **A.2** Your certificates | `ingress = { mode = "automated", tls_certificate_secret_arn = … }` (optional: `email.certificate_secret_arn`) | Create the DNS records |
| **B** Bring your own | Nothing (default) | Install your ingress controller, apply Plane's routes (module README, "Path B routes"), add your certificate, create the DNS records |

Without an email certificate, the email service uses a self-signed one (fine for receiving mail).

`terraform.tfvars.example` shows every other setting with its default. For objects, set only the fields you change,
e.g. `node_group = { desired_size = 3 }`.

## Docker mode

`deployment_mode = "docker"` runs Plane's Docker Compose stack on one EC2 instance with the bundled data services.
`ingress` defaults to path A in this mode, so set a certificate source:

| | Set in `terraform.tfvars` | After the apply |
|---|---|---|
| **A.1** Let's Encrypt | `deployment_mode = "docker"`, `acme_email` | Create the A (and MX) records from `terraform output dns_records`; the certificate is issued once the A record exists |
| **A.2** Your certificate | `deployment_mode = "docker"`, `ingress = { tls_certificate_secret_arn = … }` | Create the records |
| **Internal** | as A.2, plus `ingress.scheme = "internal"` and `allowed_cidrs` | A record to the private IP |
| **B** Your load balancer | `deployment_mode = "docker"`, `ingress = { mode = "none" }` | Point your load balancer at `instance_private_ip`:80 |

The apply waits for the stack to be healthy (20–30 minutes on a fresh install). If it fails, the output is under
`terraform output ssm_output_s3_uri`; fix the cause and run `terraform output -raw rerun_setup_command`. Until Plane
publishes the compose files at the default URL, set `docker.compose_assets_url` (see the module README).
