# Discover the EKS node group ASG so we can attach target groups to it.
# EKS managed node groups tag their ASGs with eks:cluster-name automatically.
data "aws_autoscaling_groups" "eks_nodes" {
  filter {
    name   = "tag:eks:cluster-name"
    values = [var.cluster_name]
  }
}

# Allow inbound traffic from NLB to EKS node NodePorts
resource "aws_security_group_rule" "smtp_nodeport" {
  type              = "ingress"
  from_port         = var.smtp_node_port
  to_port           = var.smtp_node_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = var.node_security_group_id
  description       = "Email NLB -> SMTP NodePort"
}

resource "aws_security_group_rule" "smtps_nodeport" {
  type              = "ingress"
  from_port         = var.smtps_node_port
  to_port           = var.smtps_node_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = var.node_security_group_id
  description       = "Email NLB -> SMTPS NodePort"
}

resource "aws_security_group_rule" "submission_nodeport" {
  type              = "ingress"
  from_port         = var.submission_node_port
  to_port           = var.submission_node_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = var.node_security_group_id
  description       = "Email NLB -> Submission NodePort"
}

# Target groups (instance target type — routes to NodePorts on worker nodes)
resource "aws_lb_target_group" "smtp" {
  name        = "${var.cluster_name}-email-smtp"
  port        = var.smtp_node_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = tostring(var.smtp_node_port)
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-email-smtp" })
}

resource "aws_lb_target_group" "smtps" {
  name        = "${var.cluster_name}-email-smtps"
  port        = var.smtps_node_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = tostring(var.smtps_node_port)
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-email-smtps" })
}

resource "aws_lb_target_group" "submission" {
  name        = "${var.cluster_name}-email-sub"
  port        = var.submission_node_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = tostring(var.submission_node_port)
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-email-sub" })
}

# Internet-facing Network Load Balancer
resource "aws_lb" "email" {
  name               = "${var.cluster_name}-email"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  enable_deletion_protection = false

  tags = merge(var.tags, { Name = "${var.cluster_name}-email-nlb" })
}

# Listeners
resource "aws_lb_listener" "smtp" {
  load_balancer_arn = aws_lb.email.arn
  port              = 25
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.smtp.arn
  }
}

resource "aws_lb_listener" "smtps" {
  load_balancer_arn = aws_lb.email.arn
  port              = 465
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.smtps.arn
  }
}

resource "aws_lb_listener" "submission" {
  load_balancer_arn = aws_lb.email.arn
  port              = 587
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.submission.arn
  }
}

# Attach each target group to every EKS node ASG so nodes are registered
# automatically as the node group scales up/down.
resource "aws_autoscaling_attachment" "smtp" {
  for_each               = toset(data.aws_autoscaling_groups.eks_nodes.names)
  autoscaling_group_name = each.value
  lb_target_group_arn    = aws_lb_target_group.smtp.arn
}

resource "aws_autoscaling_attachment" "smtps" {
  for_each               = toset(data.aws_autoscaling_groups.eks_nodes.names)
  autoscaling_group_name = each.value
  lb_target_group_arn    = aws_lb_target_group.smtps.arn
}

resource "aws_autoscaling_attachment" "submission" {
  for_each               = toset(data.aws_autoscaling_groups.eks_nodes.names)
  autoscaling_group_name = each.value
  lb_target_group_arn    = aws_lb_target_group.submission.arn
}
