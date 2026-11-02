# A newer AMI never replaces the instance (ignore_changes): unattended-upgrades patches it in place.
data "aws_ssm_parameter" "ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_instance" "this" {
  # checkov:skip=CKV2_AWS_41:The instance profile is set (iam_instance_profile); checkov can't resolve it across files.
  ami                         = data.aws_ssm_parameter.ami.insecure_value
  instance_type               = var.docker.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.instance.id]
  iam_instance_profile        = aws_iam_instance_profile.instance.name
  associate_public_ip_address = false # path A gets the Elastic IP
  monitoring                  = true
  ebs_optimized               = true

  # No key pair or user data: setup runs through SSM.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1 # containers can't reach the instance role
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.docker.root_volume_gb
    encrypted             = true
    kms_key_id            = aws_kms_key.this.arn
    delete_on_termination = true
    tags                  = merge(var.tags, { Name = "${var.name}-plane-root" })
  }

  tags = merge(var.tags, { Name = "${var.name}-plane" })

  lifecycle {
    ignore_changes = [ami]
  }
}

# All of Plane's data (/opt/plane), separate so replacing the instance keeps it.
resource "aws_ebs_volume" "data" {
  availability_zone = var.availability_zone
  type              = "gp3"
  size              = var.docker.data_volume_gb
  encrypted         = true
  kms_key_id        = aws_kms_key.this.arn
  snapshot_id       = var.docker.data_volume_snapshot_id
  final_snapshot    = true

  tags = merge(local.data_tags, { Name = "${var.name}-plane-data" })
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.this.id

  # So Postgres shuts down cleanly on replace or destroy.
  stop_instance_before_detaching = true
}
