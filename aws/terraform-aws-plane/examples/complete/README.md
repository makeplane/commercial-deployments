# Complete example

An empty AWS account to a running Plane on EKS.

```bash
cp terraform.tfvars.example terraform.tfvars   # set domain, route53_zone_id, acme_email, admin_cidrs
cp backend.hcl.example backend.hcl             # set the state bucket: state holds generated secrets
terraform init -backend-config=backend.hcl
terraform apply                                # roughly 35-45 minutes
```

Then open the `plane_url` output. Without `route53_zone_id`, create a CNAME for your domain to the
`load_balancer_dns_name` output; see "DNS and TLS" in the [module README](../../README.md).

To test without hitting Let's Encrypt rate limits, set
`acme_server = "https://acme-staging-v02.api.letsencrypt.org/directory"`.
