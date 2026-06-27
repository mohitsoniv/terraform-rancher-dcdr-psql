locals {
  subnet_id = element(tolist(data.aws_subnets.default.ids), 0)
}

# ---------------- Rancher server ----------------
resource "aws_instance" "rancher" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.rancher.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_disk_gb
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user_data/rancher.sh", {
    rancher_version = var.rancher_version
  })

  tags = { Name = "${var.name_prefix}-rancher-server" }
}

# ---------------- DC cluster nodes ----------------
resource "aws_instance" "dc_node" {
  count                       = var.dc_node_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.rancher.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_disk_gb
    volume_type = "gp3"
  }

  user_data = file("${path.module}/user_data/node.sh")

  tags = { Name = "${var.name_prefix}-dc-node-${count.index + 1}" }
}

# ---------------- DR cluster nodes (Spot) ----------------
resource "aws_instance" "dr_node" {
  count                       = 3
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.rancher.id]
  associate_public_ip_address = true

  instance_market_options {
    market_type = "spot"
    spot_options {
      instance_interruption_behavior = "terminate"
    }
  }

  root_block_device {
    volume_size = var.root_disk_gb
    volume_type = "gp3"
  }

  user_data = file("${path.module}/user_data/node.sh")

  tags = { Name = "${var.name_prefix}-dr-node-${count.index + 1}" }
}
