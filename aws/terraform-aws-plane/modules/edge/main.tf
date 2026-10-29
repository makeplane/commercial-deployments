# Static public IPs for the NLB (one per public subnet it uses) and, when a Route 53 zone is given,
# the A record. Both are known at plan time, so DNS never waits on the load balancer.

resource "aws_eip" "lb" {
  # checkov:skip=CKV2_AWS_19:Attached to the NLB (by the AWS Load Balancer Controller), not to EC2 instances.
  count  = var.ip_count
  domain = "vpc"

  tags = merge(var.tags, { Name = "${var.name}-lb-${count.index}" })
}

resource "aws_route53_record" "plane" {
  count = var.route53_zone_id == null ? 0 : 1

  zone_id = var.route53_zone_id
  name    = var.domain
  type    = "A"
  ttl     = 300
  records = aws_eip.lb[*].public_ip
}
