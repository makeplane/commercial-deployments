# Never port 22 (shell access is through SSM). On path A, port 80 serves ACME HTTP-01 and the HTTPS redirect.

locals {
  web_rules = local.automated ? flatten([
    for cidr in var.ingress.allowed_cidrs : [for port in [80, 443] : { port = port, cidr = cidr }]
  ]) : [{ port = 80, cidr = var.vpc_cidr }]

  smtp_rules = flatten([for cidr in local.smtp_cidrs : [for port in [25, 465, 587] : { port = port, cidr = cidr }]])

  ingress_rules = { for r in concat(local.web_rules, local.smtp_rules) : "${r.port}-${r.cidr}" => r }
}

resource "aws_security_group" "instance" {
  # checkov:skip=CKV2_AWS_5:Attached to the instance in instance.tf.
  name        = "${var.name}-plane-instance"
  description = "Plane (${var.name}) Docker instance"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-plane-instance" })
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.ingress_rules

  security_group_id = aws_security_group.instance.id
  description       = "Plane port ${each.value.port}"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = strcontains(each.value.cidr, ":") ? null : each.value.cidr
  cidr_ipv6         = strcontains(each.value.cidr, ":") ? each.value.cidr : null

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "all" {
  # checkov:skip=CKV_AWS_382:Egress to Docker Hub, Plane's licence server, Let's Encrypt, apt mirrors, AWS APIs and the customer's SMTP relay; no fixed list.
  security_group_id = aws_security_group.instance.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = var.tags
}

# A stable address for the customer's A record across instance replacement.
resource "aws_eip" "this" {
  count = local.public ? 1 : 0

  domain = "vpc"

  tags = merge(var.tags, { Name = "${var.name}-plane" })
}

resource "aws_eip_association" "this" {
  count = local.public ? 1 : 0

  allocation_id = aws_eip.this[0].id
  instance_id   = aws_instance.this.id
}
