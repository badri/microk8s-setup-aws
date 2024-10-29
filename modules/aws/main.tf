data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["amazon"]
}

locals {
  vms = flatten([
    for node_group in var.node_group_config : [
      for i in range(node_group.count) : {
        name = "${node_group.name}"
        type = node_group.size
        id   = node_group.id
      }
    ]
  ])
}

resource "aws_security_group" "allow_ssh" {
  name        = "security-group-${var.ssh_key_prefix}"
  description = "Allow SSH inbound traffic"

  # SSH access
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # K3s API Server
  ingress {
    description = "Kubernetes API Server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP/HTTPS for ingress
  ingress {
    description = "HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ssh"
    From = "ShapeBlock"
  }
}

# Flannel VXLAN
resource "aws_security_group_rule" "vxlan" {
  description       = "Flannel VXLAN"
  type              = "ingress"
  from_port         = 8472
  to_port           = 8472
  protocol          = "udp"
  security_group_id = aws_security_group.allow_ssh.id
  self              = true
}

# Kubelet metrics
resource "aws_security_group_rule" "kubelet" {
  description       = "Kubelet metrics"
  type              = "ingress"
  from_port         = 10250
  to_port           = 10250
  protocol          = "tcp"
  security_group_id = aws_security_group.allow_ssh.id
  self              = true
}

# etcd (only needed for HA setup)
resource "aws_security_group_rule" "etcd" {
  description       = "etcd for HA"
  type              = "ingress"
  from_port         = 2379
  to_port           = 2380
  protocol          = "tcp"
  security_group_id = aws_security_group.allow_ssh.id
  self              = true
}

resource "aws_key_pair" "ssh_key" {
  key_name   = "terraform-ssh-key-${var.ssh_key_prefix}"
  public_key = var.ssh_key
}

resource "aws_instance" "vm" {
  for_each = {
    for vm in local.vms : vm.name => vm
  }

  ami             = data.aws_ami.ubuntu.id
  instance_type   = each.value.type
  key_name        = aws_key_pair.ssh_key.key_name
  security_groups = [aws_security_group.allow_ssh.name]

  root_block_device {
    volume_type           = "gp3" # General Purpose SSD (gp3)
    volume_size           = 80    # 80 GiB
    delete_on_termination = true
  }

  tags = {
    Name        = each.value.name
    shapeblock  = "shapeblock"
    NodeGroup   = each.value.name
    NodeGroupId = each.value.id
  }
}

