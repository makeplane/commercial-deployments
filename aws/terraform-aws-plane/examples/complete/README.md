# Complete example

An empty AWS account to a running Plane on EKS.

```bash
cp terraform.tfvars.example terraform.tfvars   # set domain, route53_zone_id, acme_email, admin_cidrs
# Uncomment and fill in the S3 backend in versions.tf: state holds generated secrets.
terraform init
terraform apply                                # roughly 35-45 minutes
```

Then open the `plane_url` output. Without `route53_zone_id`, follow "DNS and TLS" in the
[module README](../../README.md) to create the DNS record and certificate.

To test without hitting Let's Encrypt rate limits, set
`acme_server = "https://acme-staging-v02.api.letsencrypt.org/directory"`.
