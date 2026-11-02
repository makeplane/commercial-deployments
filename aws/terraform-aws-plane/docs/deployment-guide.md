# Deploying Plane on AWS

This guide takes you from an AWS account to a running Plane Commercial installation, using the `terraform-aws-plane`
module. One `terraform apply` creates the network, an EKS cluster, managed databases and Plane itself. You then create
a few DNS records and, depending on the option you choose, finish the ingress setup.

Plan for about two hours. Most of that is waiting for AWS to create resources.

## Contents

1. [What gets deployed](#1-what-gets-deployed)
2. [Before you start](#2-before-you-start)
3. [Choose how traffic reaches Plane](#3-choose-how-traffic-reaches-plane)
4. [Set up Terraform state](#4-set-up-terraform-state)
5. [Configure](#5-configure)
6. [Deploy](#6-deploy)
7. [Create the DNS records](#7-create-the-dns-records)
8. [Finish the ingress setup](#8-finish-the-ingress-setup)
9. [Sign in and activate your licence](#9-sign-in-and-activate-your-licence)
10. [Day-2 operations](#10-day-2-operations)
11. [Removing the installation](#11-removing-the-installation)
12. [Troubleshooting](#12-troubleshooting)

## 1. What gets deployed

| Part | What | Default size |
|---|---|---|
| Network | A new VPC with 3 private and 3 public subnets, one NAT gateway, VPC flow logs | `10.60.0.0/16` |
| Kubernetes | Amazon EKS with one managed node group | 2 × `m7a.xlarge` (range 2–4) |
| Database | Amazon RDS for PostgreSQL, Multi-AZ DB cluster, TLS required | `db.m6gd.large`, 100 GB |
| Cache | Amazon ElastiCache (Valkey), TLS and password | `cache.t3.medium` |
| Message queue | Amazon MQ for RabbitMQ, multi-AZ cluster | `mq.m7g.medium` |
| Search | Amazon OpenSearch Service, private | 2 × `r7g.large.search` |
| File storage | Amazon S3 bucket for uploads | |
| Email | Plane's email service on its own Network Load Balancer, receiving mail for `intake.<your domain>` | |
| Plane | The Plane Commercial Helm chart, with its secrets in AWS Secrets Manager | |

**Security defaults:**
- Everything runs in private subnets. Only the load balancers and the Kubernetes API endpoint are public; limit the
  endpoint to your networks with `cluster_endpoint_public_access_cidrs`.
- Data is encrypted with a KMS key created for this installation.
- Plane reaches S3, Secrets Manager and OpenSearch through IAM roles (EKS Pod Identity). There are no access keys anywhere.
- Passwords and keys are generated for you and stored in AWS Secrets Manager.

Every size above can be changed in `terraform.tfvars`.

## 2. Before you start

### Tools

| Tool | Version | Used for |
|---|---|---|
| Terraform | 1.10 or later | The deployment |
| AWS CLI | v2 | Authentication to the cluster during the apply |
| kubectl | any recent | Checking the installation |
| Helm | 3 or later | Only if you bring your own ingress (option B) |
| jq | any | Only if you store your own certificates in Secrets Manager |

### AWS account

- **Credentials** for the target account that can create: VPC and EC2 networking, EKS, IAM roles and policies, RDS,
  ElastiCache, Amazon MQ, OpenSearch Service, S3, KMS, Secrets Manager, CloudWatch Logs, and service-linked roles. In
  practice, an administrator role.
- **A region with at least three Availability Zones.** The database needs three.
- **The OpenSearch service-linked role.** If OpenSearch has never been used in this account, create it once:
  ```bash
  aws iam create-service-linked-role --aws-service-name es.amazonaws.com
  ```
  An error saying the role already exists is fine.
- **Service quotas** in the region. Check these in the Service Quotas console:
  - On-demand standard instances: at least 16 vCPUs, which covers 4 nodes.
  - Elastic IP addresses: 1 free, for the NAT gateway.
  - VPCs and NAT gateways: 1 of each free.
  - Network Load Balancers: 2.

### Domain and DNS

- **A domain for Plane**, for example `plane.example.com`. **It can never change after installation:** your Plane licence
  is bound to it.
- **Access to the DNS zone.** You create the DNS records yourself after the apply; the module never changes your DNS.
  Any DNS provider works.
- **An email domain** for inbound email to work items. The default is `intake.<your domain>`.

### Plane licence

A Plane Commercial licence key, which you activate after installation.

## 3. Choose how traffic reaches Plane

Pick one option before you configure.

| Option | Choose it when | The module installs | You do after the apply |
|---|---|---|---|
| **A.1: Automated, Let's Encrypt** | Plane is reachable from the internet, and a free Let's Encrypt certificate is fine | Traefik ingress behind a load balancer, Plane's routes, and a Let's Encrypt certificate | Create the DNS records |
| **A.2: Automated, your certificate** | You have your own certificate, or Plane is internal only | Traefik ingress behind a load balancer, Plane's routes, and your certificate | Store the certificate in Secrets Manager first; create the DNS records |
| **B: Bring your own ingress** | You run your own ingress controller (NGINX, OpenShift, your own Traefik, AWS ALB, …) or certificate tooling | No ingress controller and no routes | Install your controller, apply Plane's routes, add the certificate, create the DNS records |

**About A.1:** Let's Encrypt checks domain ownership over HTTP, so Plane must be reachable from the whole internet on
port 80. The certificate is issued a few minutes after your DNS record points at the load balancer, and it renews
automatically. If you need to restrict who can reach Plane, choose A.2 or B.

**Email certificate (any option):** the email service uses a certificate for encrypted mail. If you don't provide one,
it generates a self-signed certificate. That's fine for receiving mail from other mail servers. To use a trusted one,
store it in Secrets Manager (next section) and set `email.certificate_secret_arn`.

### Storing a certificate in Secrets Manager (A.2 and email)

Store each certificate as a secret with two JSON keys: `tls.crt` (the full chain, PEM) and `tls.key` (the private key,
PEM).

- Create it in the **same AWS account and region** as Plane.
- Use the default `aws/secretsmanager` encryption key. Secrets encrypted with your own KMS keys can't be read.
- Use its **full ARN** in `terraform.tfvars`.
- One certificate can serve both web and email if it lists both names, for example `plane.example.com` and
  `intake.plane.example.com`.

```bash
aws secretsmanager create-secret --name plane/web-tls --region <region> \
  --secret-string "$(jq -n --rawfile crt fullchain.pem --rawfile key privkey.pem '{"tls.crt": $crt, "tls.key": $key}')"
```

Note the ARN in the output. To renew later, update the secret's value: it's picked up within an hour, and the email
service restarts automatically to use it.

## 4. Set up Terraform state

Terraform state contains generated passwords and keys, so keep it in a private, encrypted, versioned S3 bucket.

```bash
aws s3api create-bucket --bucket <state-bucket> --region <region> \
  --create-bucket-configuration LocationConstraint=<region>   # omit this line in us-east-1
aws s3api put-bucket-versioning --bucket <state-bucket> --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket <state-bucket> \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

New S3 buckets are encrypted by default. You can also use an existing bucket that meets these requirements.

## 5. Configure

Get the module at the release you were given:

```bash
git clone https://github.com/makeplane/commercial-deployments.git
cd commercial-deployments
git checkout <release-tag>
cd aws/terraform-aws-plane/examples/complete
```

Point Terraform at your state bucket:

```bash
cp backend.hcl.example backend.hcl
```

```hcl
# backend.hcl
bucket       = "<state-bucket>"
key          = "plane/terraform.tfstate"
region       = "<region>"
encrypt      = true
use_lockfile = true
```

Create your settings file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` is the only file you edit. `terraform.tfvars.example` lists every setting with its default. Set the
required values and the block for your option:

```hcl
region = "us-east-1"
name   = "plane"             # prefix for all resources, 3–20 characters; never change it
domain = "plane.example.com" # never change it

# Who can reach the Kubernetes API (Terraform needs it during the apply). Use your network's ranges.
cluster_endpoint_public_access_cidrs = ["203.0.113.0/24"]

# Option A.1: Let's Encrypt
ingress    = { mode = "automated" }
acme_email = "ops@example.com" # Let's Encrypt account email, for expiry notices

# Option A.2: your certificate (instead of the A.1 lines)
# ingress = { mode = "automated", tls_certificate_secret_arn = "arn:aws:secretsmanager:<region>:<account>:secret:plane/web-tls-..." }

# Option B: bring your own ingress. Set nothing here.

# Optional: your email certificate (any option)
# email = { certificate_secret_arn = "arn:aws:secretsmanager:<region>:<account>:secret:plane/mail-tls-..." }
```

**Common optional settings.** For objects, set only the fields you change.

| Setting | Example | Effect |
|---|---|---|
| Restrict who reaches Plane (A.2) | `ingress = { mode = "automated", tls_certificate_secret_arn = "…", allowed_cidrs = ["10.0.0.0/8"] }` | Load balancer accepts only these ranges |
| Internal load balancer (A.2) | `ingress = { …, scheme = "internal" }` | Plane reachable only from inside the VPC or connected networks |
| More nodes | `node_group = { desired_size = 3 }` | 3 nodes instead of 2 (range 2–4) |
| Cache failover | `redis = { replicas = 1 }` | A second cache node with automatic failover (the default is one node) |
| Different email domain | `email = { smtp_domain = "mail.example.com" }` | Intake addresses use this domain |
| Email without a public endpoint | `email = { load_balancer = false }` | The email service runs, but can't receive mail from the internet |
| No email | `email = { enabled = false }` | No email service and no email load balancer |
| No search | `opensearch = { enabled = false }` | No OpenSearch; Plane runs with search indexing off, so search is more limited |
| Different VPC range | `vpc_cidr = "10.80.0.0/16"` | Avoids overlap with networks you peer with |
| Extra admins | `cluster_admin_principal_arns = ["arn:aws:iam::<account>:role/<role>"]` | Cluster admin access for these IAM roles or users |
| Tags | `tags = { CostCenter = "1234" }` | Added to every resource |

When an object setting appears twice (for example two `email = { … }` lines), Terraform fails: combine the fields
into one line.

## 6. Deploy

```bash
terraform init -backend-config=backend.hcl
terraform plan -out plane.tfplan
```

Check that the plan only adds resources: `Plan: N to add, 0 to change, 0 to destroy`. Then apply:

```bash
terraform apply plane.tfplan
```

The apply takes 45–75 minutes. The database migrations alone take about 15 minutes on a new installation, so the last
step (`helm_release.plane`) runs for a while without output. That's expected.

When it finishes, connect kubectl to the cluster:

```bash
$(terraform output -raw configure_kubectl)
kubectl -n plane get pods   # all Running or Completed
```

## 7. Create the DNS records

```bash
terraform output dns_records
```

| Record | Name | Type | Value |
|---|---|---|---|
| Web (options A.1 and A.2) | your `domain` | CNAME | the `web` value: the load balancer's hostname |
| Web (option B) | your `domain` | CNAME | your own ingress controller's load balancer |
| Email | your email domain (`intake.<domain>`) | MX | `10 <email load balancer hostname>` |

- Always point at the load balancer's **hostname** with a CNAME (or an alias record in Route 53). Never create A records
  with its IP addresses: AWS assigns them and can change them.
- For a zone apex (`example.com` itself), use your DNS provider's alias or CNAME-flattening record.
- If your DNS is on Cloudflare, set the records to **DNS only** (no proxy).

## 8. Finish the ingress setup

### Option A.1

The certificate is issued a few minutes after the web DNS record resolves. Until then, browsers show a certificate
warning. Check progress:

```bash
kubectl -n plane get certificate plane-tls   # READY becomes True
kubectl -n plane get challenges               # empty once issued
```

### Option A.2

Nothing more to do. To check the certificate was loaded from Secrets Manager:

```bash
kubectl -n plane get externalsecret plane-web-tls   # STATUS SecretSynced
```

### Option B

1. **Install your ingress controller** if it isn't already in the cluster. Its load balancer needs to be reachable by
   your users; the AWS Load Balancer Controller is already installed if you want to use AWS load balancers.
2. **Add your certificate** as a Kubernetes TLS Secret named `plane-tls` in namespace `plane` (skip on OpenShift, where
   the router terminates TLS):
   ```bash
   kubectl -n plane create secret tls plane-tls --cert=fullchain.pem --key=privkey.pem
   ```
   Or let your own cert-manager create that Secret.
3. **Generate Plane's routes** for your controller from the exact values this installation uses:
   ```bash
   helm repo add plane https://helm.plane.so/
   terraform output -raw plane_helm_values > plane-values.yaml
   ```
   Then run the command for your controller. Use the chart version this installation uses (`chart_version` in
   `terraform.tfvars.example`, or your override). If you set `plane_values`, save it to a file and add it as a second
   `-f`.

   **Traefik:**
   ```bash
   helm template plane plane/plane-enterprise --version <chart_version> -n plane -f plane-values.yaml \
     --set ingress.enabled=true,ingress.controller=traefik \
     --show-only templates/ingress-traefik.yaml --show-only templates/traefik-middleware.yaml > plane-routes.yaml
   ```
   The routes use Traefik's `websecure` entry point.

   **NGINX:**
   ```bash
   helm template plane plane/plane-enterprise --version <chart_version> -n plane -f plane-values.yaml \
     --set ingress.enabled=true,ingress.controller=nginx,ingress.ingressClass=<your-ingress-class> \
     --set-string 'ingress.ingress_annotations.nginx\.ingress\.kubernetes\.io/proxy-body-size=20m' \
     --show-only templates/ingress-nginx.yaml > plane-routes.yaml
   ```

   **OpenShift:**
   ```bash
   helm template plane plane/plane-enterprise --version <chart_version> -n plane -f plane-values.yaml \
     --set ingress.enabled=true,ingress.controller=openshift \
     --show-only templates/ingress-openshift.yaml > plane-routes.yaml
   ```

   **Other controllers:** use the generated NGINX Ingress as the route table: each path, the service and port it goes
   to. Plane needs WebSocket support on `/live/` and an upload size limit of at least 20 MB.
4. **Apply the routes:**
   ```bash
   kubectl -n plane apply -f plane-routes.yaml
   ```
   Repeat steps 3 and 4 after every Plane upgrade.

## 9. Sign in and activate your licence

1. Open `https://<your domain>` and complete the setup: create the first admin account and your workspace.
2. Activate your Plane licence key, following the activation steps in Plane's documentation.
3. Configure outgoing email (SMTP), single sign-on and AI providers in the instance admin panel at
   `https://<your domain>/god-mode/`.

**Inbound email:** once the MX record resolves, mail sent to your intake addresses becomes work items. The email load
balancer accepts mail from any sender on ports 25, 465 and 587, as a mail server must.

## 10. Day-2 operations

Always change the installation through `terraform.tfvars`, then `terraform plan` and `terraform apply`. Review the plan
before applying.

| Task | How |
|---|---|
| Upgrade Plane | Use the new module release: `git fetch && git checkout <new-release-tag>`, then plan and apply. Read the release notes first. Migrations and search indexes run automatically. Option B: regenerate and re-apply your routes. |
| More capacity | Add nodes (`node_group = { desired_size = 3 }`, up to `max_size`) and Plane replicas through `plane_values`, for example `plane_values = "services: { api: { replicas: 4 }, worker: { replicas: 4 } }"`. |
| Renew your certificate (A.2, email) | Update the secret's value in Secrets Manager. Plane picks it up within an hour. Option A.1 renews automatically. |
| Backups | RDS keeps automated backups for 14 days, and takes a final snapshot if the database is deleted. S3 keeps old versions of files for 30 days. |
| Secrets | Cache and queue credentials and Plane's app keys are in Secrets Manager under `plane/<name>/`. The database password is a secret managed and rotated by RDS. |

**Never change** `name` or `domain` after installation, and never delete or change the `plane/<name>/app-keys` secret:
Plane uses those keys to encrypt data, and the licence is bound to the domain.

**Node count note:** Terraform sets the node count only when it creates the node group. To scale an existing
installation, change it in AWS:

```bash
aws eks list-nodegroups --cluster-name <name>   # the node group's name
aws eks update-nodegroup-config --cluster-name <name> --nodegroup-name <node group> \
  --scaling-config minSize=2,maxSize=4,desiredSize=3
```

## 11. Removing the installation

This deletes Plane and all its data.

1. **Option B only:** delete your routes and your ingress controller first, so its load balancer is removed
   (`kubectl -n plane delete -f plane-routes.yaml`, then uninstall the controller). A leftover load balancer stops the
   VPC from being deleted.
2. Turn off the database's deletion protection, and allow deleting the uploads bucket with its files. Without these,
   `terraform destroy` stops with an error. In `terraform.tfvars`:
   ```hcl
   postgres             = { deletion_protection = false }
   bucket_force_destroy = true
   ```
   Then `terraform apply`.
3. `terraform destroy`.
4. Delete your DNS records.

RDS keeps a final snapshot of the database, named `<name>-pg-final`. It's encrypted with the installation's KMS key,
which AWS deletes 30 days after the destroy: if you may need the data, restore or copy the snapshot with another key
before then. The secrets stay recoverable for 7 days.

To reinstall with the same `name`, first delete that snapshot, and delete the `plane/<name>/*` secrets for good
(`aws secretsmanager delete-secret --force-delete-without-recovery --secret-id <arn>`). Otherwise the apply fails
because those names are still taken.

## 12. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Browser certificate warning (A.1) | The certificate isn't issued yet: DNS doesn't resolve to the load balancer, the record is proxied, or port 80 isn't reachable from the internet | Check the record (`dig <domain>`), make it DNS-only, then `kubectl -n plane describe certificate plane-tls` and `kubectl -n plane get challenges` |
| Browser certificate warning (A.2) | The certificate secret has the wrong keys or doesn't cover the domain | Keys must be `tls.crt` and `tls.key`; `kubectl -n plane describe externalsecret plane-web-tls` |
| `Invalid value for variable "ingress"` | Option A needs exactly one certificate source, or Let's Encrypt was combined with restricted access | Set either `acme_email` or `ingress.tls_certificate_secret_arn`; with Let's Encrypt keep the load balancer public and open |
| `Warning: Check block assertion failed` (email certificate) | No email certificate given | Informational: the email service uses a self-signed certificate. Set `email.certificate_secret_arn` for a trusted one |
| Apply fails creating the OpenSearch domain with a service-linked role error | The role doesn't exist in the account | Create it (section 2) and apply again |
| Apply fails with `InsufficientInstanceCapacity` or a quota error | Service quota too low | Raise the quota (section 2) and apply again |
| `terraform plan` can't reach the cluster | Your IP isn't in `cluster_endpoint_public_access_cidrs` | Add your network's range and apply |
| `helm_release.plane` runs for a long time | Database migrations on a new installation (about 15 minutes) | Wait; check with `kubectl -n plane get pods` |
| Uploads fail (option B) | Your controller's request size limit is too low | Allow at least 20 MB |
| Live collaboration doesn't connect (option B) | WebSockets not enabled on `/live/` | Enable WebSocket support for that path |
| No inbound email | The MX record is missing or wrong | `dig MX <email domain>` must return the email load balancer's hostname |

For help, contact Plane support with the output of `terraform version`, the failing command's error, and
`kubectl -n plane get pods`.
