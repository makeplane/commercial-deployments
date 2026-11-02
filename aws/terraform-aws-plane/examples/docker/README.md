# Docker example (Quickstart)

Plane on one EC2 instance with Docker Compose, from an empty AWS account: Plane's own Caddy proxy on an Elastic IP
with a Let's Encrypt certificate, the bundled data services on an encrypted EBS volume, nightly backups to S3. For
every setting (your own certificate, a private instance, path B), use [`../complete`](../complete) with
`deployment_mode = "docker"`.

```bash
cp terraform.tfvars.example terraform.tfvars        # name, domain, acme_email
cp ../complete/backend.hcl.example backend.hcl      # the state bucket: state holds generated secrets
terraform init -backend-config=backend.hcl
terraform apply                                     # 20-30 minutes; waits until Plane is healthy
terraform output dns_records                        # create the A record (and the MX record for email)
```

Then open `https://<domain>`: the certificate is issued once the A record points at the Elastic IP. If the apply
fails, read the setup output under `terraform output ssm_output_s3_uri`, fix the cause and run
`terraform output -raw rerun_setup_command` (or apply again).
