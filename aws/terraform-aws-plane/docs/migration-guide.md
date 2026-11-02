# Moving an existing Plane installation to the module

This guide moves a Plane Commercial installation that runs on AWS with the older `aws/terraform` module and the
`kustomize/` manifests onto a new installation created with the `terraform-aws-plane` module. Your workspaces, work
items, pages, files, users, instance settings and licences come with you. Plane keeps the same domain.

The new installation is built next to the old one, in a new VPC and EKS cluster. The old one stays untouched until
you've checked the new one, so you can switch back at any point.

Plan for a day of preparation and a maintenance window of one to three hours, during which Plane is unavailable. The
window is mostly the database copy and Plane's first start, so its length depends on the size of your database:
rehearse the copy (step 6) to know yours.

Read the [deployment guide](deployment-guide.md) first. This guide refers to it for everything that's the same as a
new installation.

## Contents

1. [How the move works](#1-how-the-move-works)
2. [What moves and how](#2-what-moves-and-how)
3. [Before you start](#3-before-you-start)
4. [Pre-flight checklist](#4-pre-flight-checklist)
5. [Collect what you need from the old installation](#5-collect-what-you-need-from-the-old-installation)
6. [Prepare the new installation](#6-prepare-the-new-installation)
7. [Move: the maintenance window](#7-move-the-maintenance-window)
8. [Verify](#8-verify)
9. [Roll back](#9-roll-back)
10. [Remove the old installation](#10-remove-the-old-installation)
11. [Troubleshooting](#11-troubleshooting)

## 1. How the move works

```
 Days before                         Maintenance window                              After
 ───────────                         ──────────────────                              ─────
 Store your app keys       ─►  Stop the old Plane                          ─►  Check the new installation
 Create the infrastructure     Copy the database into the new one             Remove the old one
   (everything but Plane)      Copy the remaining files                         (after a few weeks)
 Copy the files                Install Plane (it upgrades the database)
 Rehearse the database copy    Rebuild the search indexes
                               Switch DNS
```

Two things make the move safe:

- **Plane starts for the first time on your data.** The first apply creates everything except Plane itself. Plane is
  installed only after your database has been copied in, so it never runs on an empty database and never creates a
  second instance with the licence server.
- **Your app keys come with you.** Plane encrypts stored data with keys it reads at startup: instance settings such as
  the SMTP password and single sign-on secrets, integration tokens, and the instance key that identifies your
  licence. A new installation normally generates new keys. Here you store your existing keys in AWS Secrets Manager
  and pass the secret to the module (`app_keys_secret_arn`). With different keys, this data can't be decrypted, and
  Plane doesn't always report an error.

## 2. What moves and how

| Data | Old installation | How it moves |
|---|---|---|
| Database | RDS for PostgreSQL, database `plane` | Copied with `pg_dump` and `pg_restore` into the new RDS database. Plane upgrades it to the new version on its first start |
| Files (uploads, attachments, images) | S3 bucket | Copied to the new bucket with `aws s3 sync`. Plane stores each file's path within the bucket, not the bucket name, so the copies work as they are |
| App keys | Kubernetes Secrets in the old namespace | Stored by you in Secrets Manager (step 6.1) |
| Instance settings (admin panel: SMTP, single sign-on, AI providers), users, sessions | Database | With the database. Signed-in users stay signed in |
| Licences | Database, plus the licence server | With the database (section 6.2 has the details) |
| Search indexes | OpenSearch | Not copied: rebuilt from the database after the move |
| Cache | ElastiCache | Not copied: it only holds data Plane can recreate |
| Queued background tasks | Amazon MQ | Not copied: the old workers finish them before the copy |
| Plane AI data (only if you run Plane AI) | Database `plane_pi` | Copied like the main database (step 7.3) |
| Settings in `vars.yaml` and `secrets-vars.yaml` | Your overlay | Re-created by the module. Settings you changed, other than those this guide covers, go in `plane_values` |

The new installation uses new endpoints and passwords for the database, cache, queue and search. Plane gets them from
the module, so you don't carry any of them over.

## 3. Before you start

You need everything in the [deployment guide, section 2](deployment-guide.md#2-before-you-start), plus:

| Item | Why |
|---|---|
| `kubectl` access to the old cluster | To read the old settings and keys, stop Plane, and copy the database |
| `jq` and `openssl` | To build the app keys secret |
| Permission to read the old S3 bucket and write to the new one | To copy files. These steps assume both installations are in the same AWS account |
| Access to the DNS zone | To switch the records at the end of the window |
| A way to reach your users | To announce the maintenance window |
| Free disk space on your computer | The database copy passes through it: about the size of your database, often less (the dump is compressed) |

**Keep these the same as today:**
- **The domain.** Your licence is bound to it, and stored links use it. The new installation must use the same
  `domain`.
- **The email domain**, if you receive email into work items. Intake addresses use it, so set `email.smtp_domain` to
  the domain your MX record serves today.

**Choose a new `name`.** It must differ from the old installation's `cluster_name`: the module names the EKS cluster
after it, and both clusters exist at the same time.

## 4. Pre-flight checklist

Work through this list before you book the window.

- [ ] The old installation is healthy: every pod is running and Plane works.
- [ ] You know the old installation's Plane version (step 5). If it's newer than the module's `plane_version`
      (`v4.0.1` by default), stop and contact Plane support: a database can't be moved to an older version.
- [ ] You've chosen a `name` that differs from the old `cluster_name`, and a `vpc_cidr` that doesn't overlap your
      networks (the default `10.60.0.0/16` doesn't overlap the old module's default `10.0.0.0/16`).
- [ ] You've chosen how traffic reaches Plane (option A.1, A.2 or B in the
      [deployment guide](deployment-guide.md#3-choose-how-traffic-reaches-plane)). For the shortest window, use your
      own certificate (A.2 or B): with Let's Encrypt (A.1), the certificate is issued only after DNS points at the new
      installation, so browsers show a warning for a few minutes after the switch.
- [ ] Your certificates are in Secrets Manager (A.2, and the email certificate if you use one).
- [ ] The app keys secret exists and holds all eight keys (step 6.1).
- [ ] The infrastructure is created and the files are pre-copied (steps 6.3 and 6.4).
- [ ] You've rehearsed the database copy and know how long it takes (step 6.5).
- [ ] You've lowered the TTL of your Plane DNS records (web and MX) to 300 seconds or less, at least one old TTL
      before the window.
- [ ] You've written down the current values of those DNS records, for a rollback.
- [ ] Your users know about the window.

## 5. Collect what you need from the old installation

Connect kubectl to both clusters under fixed names, so every command says which cluster it's for:

```bash
aws eks update-kubeconfig --region <old-region> --name <old-cluster-name> --alias plane-old
export OLD_NS=plane-managed   # the old installation's namespace (the managed overlay's default)
```

Read the settings Plane runs with from the old api pod:

```bash
old_env() { kubectl --context plane-old -n "$OLD_NS" exec deploy/plane-api-wl -- printenv "$1"; }

kubectl --context plane-old -n "$OLD_NS" get deploy plane-api-wl \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'   # Plane version, e.g. ...:v3.3.3
old_env APP_DOMAIN           # your domain: use it as domain
old_env AWS_S3_BUCKET_NAME   # the old bucket
old_env MACHINE_SIGNATURE    # Plane 3.x and earlier: use it as machine_signature
```

Note:
- **The version.** Plane 3.x and earlier identify the installation to the licence server differently from Plane 4
  (section 6.2): you'll need the `MACHINE_SIGNATURE` value. If it prints nothing on a 3.x installation, contact Plane
  support before going further.
- **The email domain** your MX record serves today (`dig MX <email domain>`), if you use inbound email.
- **The old load balancer's hostname** your web record points at, for a rollback.

## 6. Prepare the new installation

None of this affects the old installation: do it in the days before the window.

### 6.1 Store the app keys in Secrets Manager

The secret holds eight keys as one JSON object. Three of them encrypt your data and must be copied exactly:

| Key | Protects | Value |
|---|---|---|
| `SECRET_KEY` | Instance settings (SMTP password, single sign-on and AI provider secrets), the instance key, sessions | Copied from the old installation |
| `AES_SECRET_KEY` | Integration tokens and application secrets | Copied from the old installation |
| `AES_SALT` | The same, together with `AES_SECRET_KEY` | Copied; installations that never set it use `aes-salt` |
| `LIVE_SERVER_SECRET_KEY`, `PI_INTERNAL_SECRET`, `SILO_HMAC_SECRET_KEY`, `CURSOR_WEBHOOK_SECRET`, `RUNNER_HMAC_SECRET_KEY` | Requests between Plane's own services; nothing stored | New values |

Build the JSON from the running old installation, store it, and delete the local file:

```bash
jq -n \
  --arg SECRET_KEY             "$(old_env SECRET_KEY)" \
  --arg AES_SECRET_KEY         "$(old_env AES_SECRET_KEY)" \
  --arg AES_SALT               "$(old_env AES_SALT || echo aes-salt)" \
  --arg LIVE_SERVER_SECRET_KEY "$(openssl rand -hex 24)" \
  --arg PI_INTERNAL_SECRET     "$(openssl rand -hex 24)" \
  --arg SILO_HMAC_SECRET_KEY   "$(openssl rand -hex 24)" \
  --arg CURSOR_WEBHOOK_SECRET  "$(openssl rand -hex 24)" \
  --arg RUNNER_HMAC_SECRET_KEY "$(openssl rand -hex 24)" \
  '$ARGS.named' > app-keys.json

jq 'map_values(length)' app-keys.json   # every key present, none 0

aws secretsmanager create-secret --region <region> --name plane/<name>/app-keys-moved \
  --description "Plane app keys moved from the old installation. Never change or delete." \
  --secret-string file://app-keys.json
rm app-keys.json
```

Note the `ARN` in the output: it's your `app_keys_secret_arn`.

- Create it in the **same account and region** as the new installation, with the default `aws/secretsmanager`
  encryption key (the command above does both).
- **Never change or delete this secret** while the installation exists. Treat it like the database: back up its value
  somewhere safe.
- `AES_SALT || echo aes-salt`: the old manifests never set `AES_SALT`, so Plane used its built-in `aes-salt`. Keep that
  value.

### 6.2 Licences

Your licences are tied to your domain and to the instance identity stored in the database, so they come with the
database. How Plane carries the identity over depends on the old version:

- **Plane 4.x:** the database already holds the instance's key pair, encrypted with `SECRET_KEY`. Nothing more to do.
- **Plane 3.x and earlier:** on its first start, Plane 4 creates a key pair for the instance and asks the licence server
  to move your licences to it. The licence server recognises your installation by its instance ID (in the database),
  its domain and its `MACHINE_SIGNATURE`. The new installation would compute a different signature, so pass the old one
  as `machine_signature`.

The move to the new key happens once. That's why Plane must not start on a copy of your production database before the
window (step 6.5). If the licence server refuses the move, Plane registers as a new instance and logs that your
licences must be re-activated: see [troubleshooting](#11-troubleshooting).

### 6.3 Configure and create the infrastructure

Set up Terraform state and the configuration as in the [deployment guide, sections 4 and
5](deployment-guide.md#4-set-up-terraform-state), and add to `terraform.tfvars`:

```hcl
name   = "plane-v4"          # not the old cluster_name
domain = "plane.example.com" # exactly the old APP_DOMAIN

app_keys_secret_arn = "arn:aws:secretsmanager:<region>:<account>:secret:plane/<name>/app-keys-moved-AbCdEf"
machine_signature   = "<old MACHINE_SIGNATURE>" # Plane 3.x and earlier only

# Inbound email: the domain your MX record serves today
email = { smtp_domain = "intake.plane.example.com" }
```

Set `app_keys_secret_arn` and `machine_signature` from the very first apply, and never remove them: removing
`app_keys_secret_arn` later makes the module generate new keys.

Now create everything **except Plane**. Targeting the add-ons and the load balancer brings in the network, the cluster
and the data services they depend on:

```bash
terraform init -backend-config=backend.hcl
terraform plan -target=module.plane.module.addons -target=module.plane.module.edge -out infra.tfplan
terraform apply infra.tfplan
```

Terraform warns that resource targeting is in effect: that's expected here, and only here. The apply takes 30–60
minutes.

Then connect kubectl and look up what the next steps need:

```bash
aws eks update-kubeconfig --region <region> --name <name> --alias plane-new

NEW_BUCKET=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '<name>-uploads-')].Name" --output text)
NEW_DB_HOST=$(aws rds describe-db-clusters --region <region> --db-cluster-identifier <name>-pg \
  --query 'DBClusters[0].Endpoint' --output text)
NEW_DB_SECRET=$(aws rds describe-db-clusters --region <region> --db-cluster-identifier <name>-pg \
  --query 'DBClusters[0].MasterUserSecret.SecretArn' --output text)
echo "$NEW_BUCKET $NEW_DB_HOST"
```

**Options A.1 and A.2:** the load balancer already exists. Its hostname is the value for your web DNS record:

```bash
aws elbv2 describe-load-balancers --region <region> --names <name>-traefik \
  --query 'LoadBalancers[0].DNSName' --output text
```

**Option B:** install your ingress controller now ([deployment guide, section 8](deployment-guide.md#option-b),
step 1), so its load balancer exists before the window. You apply Plane's routes after the window's apply.

### 6.4 Copy the files

Copy the files now, while the old installation runs. The final copy in the window then only moves what changed:

```bash
aws s3 sync "s3://<old bucket>" "s3://$NEW_BUCKET" --only-show-errors
```

The new bucket encrypts the copies with the new installation's KMS key.

### 6.5 Rehearse the database copy

Run [step 7.3](#73-copy-the-database) now, without stopping the old installation, to check it works and to time it.
Then run the checks in [step 7.4](#74-check-the-copy), and empty the new database again:

```bash
kubectl --context plane-new -n plane-migration exec db-restore -- \
  psql -d postgres -c 'DROP DATABASE plane' -c 'CREATE DATABASE plane'
```

**Don't install Plane on this copy** (no full `terraform apply` yet). Plane's first start moves the licence identity
(section 6.2), which happens only once, and the window's copy would then no longer match it.

Also check whether the database holds links to the old bucket:

```bash
kubectl --context plane-new -n plane-migration exec -i db-restore -- pg_restore -f - < plane.dump \
  | grep -c "<old bucket>"
```

`0` is the expected result: Plane stores file paths, not bucket URLs. If the count isn't 0, some content (typically
from very old Plane versions) links to the old bucket directly: keep the old bucket until you've checked those
items, and contact Plane support.

## 7. Move: the maintenance window

### 7.1 Stop the old installation

Save the current replica counts, for a rollback:

```bash
kubectl --context plane-old -n "$OLD_NS" get deploy,statefulset \
  -o jsonpath='{range .items[*]}{.kind}/{.metadata.name} {.spec.replicas}{"\n"}{end}' > old-replicas.txt
```

Stop everything that accepts or creates work, but leave the workers and consumers running, so they finish the
queued background tasks (notifications, webhooks, imports):

```bash
kubectl --context plane-old -n "$OLD_NS" get deploy -o name | grep -E 'worker|consumer' | grep -v beat > workers.txt
kubectl --context plane-old -n "$OLD_NS" get deploy -o name | grep -v -x -f workers.txt \
  | xargs kubectl --context plane-old -n "$OLD_NS" scale --replicas=0
```

Plane is now down for users. Wait until the workers are idle, typically a few minutes: their logs stop showing
new tasks.

```bash
kubectl --context plane-old -n "$OLD_NS" logs deploy/plane-worker-wl --since=2m
```

Then stop the rest:

```bash
xargs kubectl --context plane-old -n "$OLD_NS" scale --replicas=0 < workers.txt
kubectl --context plane-old -n "$OLD_NS" scale statefulset --all --replicas=0
kubectl --context plane-old -n "$OLD_NS" get pods   # nothing left but Completed jobs
```

Don't re-apply the old Kustomize overlay during the window: it would start the old installation again.

### 7.2 Copy the remaining files

```bash
aws s3 sync "s3://<old bucket>" "s3://$NEW_BUCKET" --only-show-errors
```

### 7.3 Copy the database

The database goes from a temporary pod in the old cluster, through your computer, to a temporary pod in the new
cluster. Neither database is reachable from outside its VPC, and this way neither VPC needs opening.

**Dump** the old database. The pod reads the connection string from the old installation's own Secret:

```bash
kubectl --context plane-old -n "$OLD_NS" apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: plane-db-dump
spec:
  restartPolicy: Never
  containers:
    - name: postgres
      image: postgres:15-alpine
      command: ["sleep", "infinity"]
      env:
        - name: DATABASE_URL
          valueFrom: { secretKeyRef: { name: plane-app-secrets, key: DATABASE_URL } }
EOF
kubectl --context plane-old -n "$OLD_NS" wait --for=condition=Ready pod/plane-db-dump

kubectl --context plane-old -n "$OLD_NS" exec plane-db-dump -- \
  sh -c 'pg_dump --format=custom --no-owner --no-privileges --dbname="$DATABASE_URL"' > plane.dump
echo "exit $?"; ls -lh plane.dump
```

The exit code must be 0. If your installation reads its database password from Secrets Manager instead (the
`RDS_SECRET_ARN` setup), put a `postgresql://<user>:<password>@<host>:5432/plane` connection string in `DATABASE_URL`
instead.

**Restore** into the new database, as the new database's master user (Plane uses the same user). The pod takes the
password from a temporary Secret:

```bash
kubectl --context plane-new create namespace plane-migration
kubectl --context plane-new -n plane-migration create secret generic new-db --from-literal=PGPASSWORD="$(
  aws secretsmanager get-secret-value --region <region> --secret-id "$NEW_DB_SECRET" \
    --query SecretString --output text | jq -r .password)"

kubectl --context plane-new -n plane-migration apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: db-restore
spec:
  restartPolicy: Never
  containers:
    - name: postgres
      image: postgres:15-alpine
      command: ["sleep", "infinity"]
      env:
        - { name: PGHOST, value: "$NEW_DB_HOST" }
        - { name: PGUSER, value: plane }
        - { name: PGDATABASE, value: plane }
        - { name: PGSSLMODE, value: require }
        - name: PGPASSWORD
          valueFrom: { secretKeyRef: { name: new-db, key: PGPASSWORD } }
EOF
kubectl --context plane-new -n plane-migration wait --for=condition=Ready pod/db-restore

kubectl --context plane-new -n plane-migration exec -i db-restore -- \
  pg_restore --no-owner --no-privileges --no-comments --exit-on-error --single-transaction --dbname=plane < plane.dump
echo "exit $?"
```

- `--no-owner --no-privileges`: the old tables belong to the old master user (`postgres` by default). Restored this
  way, they belong to `plane`, the user the new installation connects as.
- `--single-transaction --exit-on-error`: if anything fails, nothing is restored, and you can fix the cause and run it
  again.
- `PGSSLMODE=require`: the new database accepts only encrypted connections.
- The database password is managed by RDS and rotated every 7 days. If the restore fails to sign in, re-create the
  `new-db` Secret and the pod.

**Plane AI only** (if the old installation ran the `pi-service` component): dump its database the same way, with its
connection string (`PLANE_PI_DATABASE_URL`), then create the database and restore into it:

```bash
kubectl --context plane-new -n plane-migration exec db-restore -- psql -d postgres -c 'CREATE DATABASE plane_pi'
kubectl --context plane-new -n plane-migration exec -i db-restore -- \
  pg_restore --no-owner --no-privileges --no-comments --exit-on-error --single-transaction --dbname=plane_pi < plane_pi.dump
```

and set `enable_components = { pi = true }` in `terraform.tfvars`.

### 7.4 Check the copy

Compare a few counts between the two databases. They must match:

```bash
Q="SELECT (SELECT count(*) FROM workspaces) AS workspaces, (SELECT count(*) FROM issues) AS work_items,
   (SELECT count(*) FROM file_assets) AS files, (SELECT count(*) FROM users) AS users"
kubectl --context plane-old -n "$OLD_NS" exec plane-db-dump -- sh -c "psql \"\$DATABASE_URL\" -c \"$Q\""
kubectl --context plane-new -n plane-migration exec db-restore -- psql -c "$Q"
kubectl --context plane-new -n plane-migration exec db-restore -- psql -c 'SELECT instance_id, domain FROM instances'
```

The `instances` row must show your domain and an instance ID.

### 7.5 Install Plane

Now apply the whole configuration:

```bash
terraform plan -out plane.tfplan    # only additions, all under module.plane.module.plane
terraform apply plane.tfplan
```

Plane's migration job upgrades your database to the new version, and then Plane starts on it. Expect 15–45 minutes,
depending on the size of the database and how old the previous version is. Follow progress:

```bash
kubectl --context plane-new -n plane get jobs,pods
kubectl --context plane-new -n plane logs -f job/$(kubectl --context plane-new -n plane get jobs -o name \
  | grep api-migrate | tail -1 | cut -d/ -f2)
```

Check that the licence identity came across:

```bash
kubectl --context plane-new -n plane exec deploy/plane-api-wl -- python manage.py licence_migration status
```

| `key adoption` | Meaning |
|---|---|
| `adopted` | Plane 3.x database: the licences moved to the new instance key |
| `not needed` | Plane 4.x database: the instance key came with the database |
| `pending` | The licence server couldn't be reached or answered with a temporary error; Plane retries on its own. Check that the cluster can reach the internet |
| `new_instance:…` | The licence server refused the move: see [troubleshooting](#11-troubleshooting) |

`instance_id` must be the one from step 7.4.

### 7.6 Rebuild the search indexes

The chart's job has created the indexes, empty. Fill them from the database:

```bash
kubectl --context plane-new -n plane exec deploy/plane-api-wl -- python manage.py manage_search_index list
kubectl --context plane-new -n plane exec deploy/plane-api-wl -- \
  python manage.py manage_search_index --background document index --force
```

`--background` queues the work for the workers, so you can go on: search results fill in over the next minutes to
hours, depending on your data.

### 7.7 Switch DNS

1. **Option B:** apply Plane's routes now ([deployment guide, section 8](deployment-guide.md#option-b), steps 2–4).
2. Point your web record at the new load balancer, as in the
   [deployment guide, section 7](deployment-guide.md#7-create-the-dns-records):
   ```bash
   terraform output dns_records
   ```
3. Point your email domain's MX record at the new email load balancer (`email_mx` in the same output). Mail sent
   during the window waits on the senders' side and is retried, usually for several days.
4. **Option A.1:** the certificate is issued a few minutes after the web record resolves to the new load balancer:
   ```bash
   kubectl --context plane-new -n plane get certificate plane-tls   # READY becomes True
   ```

Old DNS answers can be cached for up to the old TTL, so a few users may still reach the old, stopped installation for
a while.

Remove the temporary pods and Secret:

```bash
kubectl --context plane-new delete namespace plane-migration
kubectl --context plane-old -n "$OLD_NS" delete pod plane-db-dump
```

Keep `plane.dump` until you've removed the old installation, then delete it: it holds all your data.

## 8. Verify

| Check | How | If it fails |
|---|---|---|
| Plane runs | `kubectl --context plane-new -n plane get pods`: all Running or Completed | [Troubleshooting](#11-troubleshooting) |
| Sign-in | Open `https://<domain>`; users already signed in stay signed in | Wrong `SECRET_KEY` signs everyone out: check the app keys secret |
| Your data | Workspaces, projects, work items and pages are there, with their history | Compare the counts (step 7.4) |
| Files | Open work items with attachments and pages with images | Re-run the file copy (step 7.2) |
| Instance settings | In `/god-mode/`, send a test email; sign in with single sign-on if you use it | Empty or failing secrets mean a wrong `SECRET_KEY` |
| Integrations | Open an integration (GitHub, GitLab, Slack) and check it's still connected | Failing integrations mean a wrong `AES_SECRET_KEY` or `AES_SALT` |
| Licences | Paid features are on; `licence_migration status` as in step 7.5 | [Troubleshooting](#11-troubleshooting) |
| Live editing | Two people edit the same page | Option B: WebSockets on `/live/` |
| Search | Search for a work item once indexing is done | Re-run `document index` (step 7.6) |
| Inbound email | Send an email to a project's intake address | `dig MX <email domain>` |

Keep the old installation stopped, not deleted, until you're satisfied: two to four weeks is typical.

## 9. Roll back

**Before the DNS switch,** the old installation hasn't changed. Start it again:

```bash
while read -r obj n; do kubectl --context plane-old -n "$OLD_NS" scale "$obj" --replicas="$n"; done < old-replicas.txt
```

**After the DNS switch,** do the same, then point the web and MX records back at the old values you wrote down.
Everything users changed on the new installation since the switch is lost: the old installation has its data from
the start of the window.

**Licences after a rollback (Plane 3.x and earlier):** once `licence_migration status` shows `adopted`, the licence
server links your licences to the new installation's key. Contact Plane support before you roll back after that point,
so they can confirm your licences on the old installation.

To retry the move later, destroy the new installation ([deployment guide, section
11](deployment-guide.md#11-removing-the-installation)), but keep the app keys secret, then start again at step 6.3.

## 10. Remove the old installation

When you're sure you won't roll back:

1. **Keep a copy of the old database**, for example a manual snapshot:
   ```bash
   aws rds create-db-cluster-snapshot --region <old-region> \
     --db-cluster-identifier <old-cluster-name>-postgres --db-cluster-snapshot-identifier <old-cluster-name>-before-removal
   ```
2. **Delete what Kubernetes created in AWS**, or `terraform destroy` can't delete the VPC: the old Plane namespace
   and the ingress controller you installed, with its load balancer.
   ```bash
   kubectl --context plane-old delete namespace "$OLD_NS"
   helm --kube-context plane-old uninstall <your ingress controller release> -n <its namespace>
   ```
3. **Empty the old bucket.** The old module doesn't delete a bucket with files in it. Check the new bucket has every
   file first.
   ```bash
   aws s3 rm "s3://<old bucket>" --recursive
   ```
4. **Destroy** from the directory of your old Terraform configuration: `terraform destroy`. The old module keeps a
   final database snapshot (`<old-cluster-name>-postgres-final-snapshot`) and deletes its secrets at once.
5. **Delete what you created by hand** for the old installation: the IAM user and access keys for S3, an ACM
   certificate (ALB setups), the old DNS records you no longer use.

Don't delete the app keys secret you created in step 6.1: the new installation uses it.

## 11. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Invalid value for variable "app_keys_secret_arn"` | Not a full secret ARN, or another account or region | Use the full ARN printed by `create-secret`, in the new installation's account and region |
| Plane pods stuck in `CreateContainerConfigError`; the apply waits | The app keys Secret can't be synced: a key is missing from the JSON, or the secret uses another KMS key | `kubectl -n plane describe externalsecret plane-app-keys`. Add the missing key with `aws secretsmanager put-secret-value`, or re-create the secret with the default key |
| `pg_dump` fails to connect | The connection string is wrong or the old database password was rotated | Check `DATABASE_URL` in the old `plane-app-secrets` Secret; the old installation must work with it |
| `pg_restore` stops with an error | The new database isn't empty (a rehearsal copy), or the dump uses an extension the new database can't create | Empty the database (step 6.5) and run it again. For an extension error, send the message to Plane support |
| The migration job fails | A database migration failed on your data | `kubectl -n plane logs job/<migrate job>`. Your old installation is untouched: roll back (section 9) and contact Plane support with the log |
| `licence_migration status` shows `key adoption: new_instance:…` | The licence server refused to move the licences: `machine_signature` missing or wrong, or a rehearsal already moved them | Paid features stay off until you delink each licence in the Plane customer portal and activate it again in Plane with its licence key. Contact Plane support |
| `key adoption: pending` for long | Plane can't reach the licence server | Check the cluster's outbound internet access (NAT gateway); then `python manage.py licence_migration retry` |
| Users are signed out; SMTP or single sign-on settings are empty | `SECRET_KEY` differs from the old installation's | Fix the app keys secret, then restart: `kubectl -n plane rollout restart deploy` |
| Integrations fail to decrypt tokens | `AES_SECRET_KEY` or `AES_SALT` differs | Same. Installations that never set `AES_SALT` need `aes-salt` |
| Search returns nothing | Indexes still filling, or never filled | `manage_search_index list`, then step 7.6 |
| Images or attachments missing | Files not copied, or copied after the item was created | Re-run `aws s3 sync` from the old bucket |
| Intake addresses changed | `email.smtp_domain` differs from the old email domain | Set it to the old email domain and apply |

For help, contact Plane support with the old and new Plane versions, the output of `licence_migration status`, and
the failing command's error.
