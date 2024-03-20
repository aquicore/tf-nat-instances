resource "aws_launch_template" "this" {
  for_each = var.multi_az ? toset(local.availability_zones) : toset([local.availability_zones[0]])

  name_prefix   = "${var.name_prefix}-nat-${each.value}"
  image_id      = var.image_id
  instance_type = var.instance_type
  user_data     = base64encode(data.template_file.userdata[each.value].rendered)

  iam_instance_profile {
    name = aws_iam_instance_profile.this.name
  }
  network_interfaces {
    associate_public_ip_address = true
    security_groups = [aws_security_group.external.id]
  }
}

resource "aws_autoscaling_group" "this" {
  for_each = var.multi_az ? toset(local.availability_zones) : toset([local.availability_zones[0]])
  name                      = "${var.name_prefix}-nat-${each.value}"
  max_size                  = 1
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 1
  vpc_zone_identifier       = [local.public_subnets[each.value]]

  launch_template {
    id      = aws_launch_template.this[each.value].id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-nat-${each.value}"
    propagate_at_launch = true
  }

  timeouts {
    delete = "15m"
  }
}

resource "aws_security_group" "external" {
  name         = "${var.name_prefix}-nat-external"
  description  = "SG for test nat instance, allows everything"

  vpc_id = var.vpc_id

  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

locals {
  private_subnets = {
    for subnet_id in var.private_subnet_ids : data.aws_subnet.private[subnet_id].availability_zone => subnet_id
  }
  public_subnets = {
    for subnet_id in var.public_subnet_ids : data.aws_subnet.public[subnet_id].availability_zone => subnet_id
  }
  availability_zones = sort(keys(local.private_subnets))
}

data "aws_subnet" "private"{
  for_each = toset(var.private_subnet_ids)
  id = each.value
}

data "aws_subnet" "public"{
  for_each = toset(var.public_subnet_ids)
  id = each.value
}

resource "aws_network_interface" "internal" {
  for_each = var.multi_az ? toset(local.availability_zones) : toset([local.availability_zones[0]])
  subnet_id       = local.private_subnets[each.value]
  security_groups = [aws_security_group.internal.id]
  source_dest_check = false
}

data "aws_route_table" "private" {
  for_each = toset(local.availability_zones)

  subnet_id = local.private_subnets[each.value]
}

resource "aws_route" "gateway" {
  for_each = toset(local.availability_zones)

  route_table_id         = data.aws_route_table.private[each.value].id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = var.multi_az ? aws_network_interface.internal[each.value].id : aws_network_interface.internal[local.availability_zones[0]].id
}

data "template_file" "userdata" {
  for_each = var.multi_az ? toset(local.availability_zones): toset([local.availability_zones[0]])
  template = file("${path.module}/include/userdata.yml.tmpl")

  vars = {
    bootstrap_b64 = base64encode(data.template_file.bootstrap[each.value].rendered)
  }
}

data "template_file" "bootstrap" {
  for_each = var.multi_az ? toset(local.availability_zones) : toset([local.availability_zones[0]])
  template = file("${path.module}/include/bootstrap.sh.tmpl")

  vars = {
    eni_id         = aws_network_interface.internal[each.value].id
    vpc_cidr       = data.aws_vpc.this.cidr_block
    subnet_gw_addr = cidrhost(
      data.aws_subnet.private[local.private_subnets[each.value]].cidr_block, 1)
  }
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "aws_security_group" "internal" {
  name         = "${var.name_prefix}-nat-internal"
  description  = "SG for test nat instance, allows everything"

  vpc_id = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }

  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
