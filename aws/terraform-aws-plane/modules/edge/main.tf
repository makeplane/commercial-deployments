# The NLB in front of Traefik and, when a Route 53 zone is given, the DNS record. The AWS Load
# Balancer Controller creates the NLB with AWS-assigned public IPs, which can change, so DNS always
# points at its hostname. The NLB has a fixed name, so it's looked up once Traefik is installed.

# Read the NLB only after Traefik's Service has it (helm waits for the LoadBalancer address).
resource "terraform_data" "addons_ready" {
  input = var.addons_ready
}

data "aws_lb" "traefik" {
  name = var.load_balancer_name

  depends_on = [terraform_data.addons_ready]
}

resource "aws_route53_record" "plane" {
  count = var.route53_zone_id == null ? 0 : 1

  zone_id = var.route53_zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = data.aws_lb.traefik.dns_name
    zone_id                = data.aws_lb.traefik.zone_id
    evaluate_target_health = false
  }
}

# MX for Plane's email intake domain, when the module has the zone. The domain must be in that zone.
resource "aws_route53_record" "email_mx" {
  count = var.route53_zone_id != null && var.email_smtp_domain != null ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.email_smtp_domain
  type    = "MX"
  ttl     = 300
  records = ["10 ${var.email_load_balancer_dns_name}"]
}
