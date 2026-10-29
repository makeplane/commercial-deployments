# Complete example

An empty AWS account to a running Plane on EKS. **`terraform.tfvars` is the one place to configure it:** this example
declares every module input under the same name and passes it straight through, and anything you don't set keeps the
module's default.

```bash
cp terraform.tfvars.example terraform.tfvars   # set name and domain; uncomment anything else you want to change
cp backend.hcl.example backend.hcl             # set the state bucket: state holds generated secrets
terraform init -backend-config=backend.hcl
terraform apply                                # 45-75 minutes on a fresh install
```

`terraform.tfvars.example` shows every setting with its default (commented), then a few examples. For objects, set
only the fields you change, e.g. `node_group = { desired_size = 3 }`.

Then open the `plane_url` output. Without `route53_zone_id`, create a CNAME for your domain to the
`load_balancer_dns_name` output; see "DNS and TLS" in the [module README](../../README.md).
