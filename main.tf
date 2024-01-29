locals {
  vms = flatten([
    for node_group in var.node_group_config : [
      for i in range(node_group.count) : {
        name = "${node_group.name}"
        size = node_group.size
        id   = node_group.id
      }
    ]
  ])
}

resource "random_id" "ssh_key_id" {
  byte_length = 8
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
}

resource "random_password" "registry_password" {
  length  = 30
  upper   = false
  special = false
}


module "aws_vms" {
  source            = "./modules/aws"
  count             = var.cloud_provider == "aws" ? 1 : 0
  ssh_key_prefix    = random_id.ssh_key_id.hex
  ssh_key           = tls_private_key.ssh_key.public_key_openssh
  node_group_config = var.node_group_config

  providers = {
    aws = aws.aws
  }
}

locals {
  selected_module = (var.cloud_provider == "aws") ? module.aws_vms[0] : null
}

locals {
  inventory = templatefile("${path.module}/hosts.tpl", {
    ha_host      = local.selected_module.ha_host
    ha_ip        = local.selected_module.ha_ip
    node_groups  = var.node_group_config
    vms          = local.selected_module.vm_info
    email        = var.email
    dns          = var.dns
    tld          = var.tld
    sb_url       = var.sb_url
    cluster_uuid = var.cluster_uuid
    password     = random_password.registry_password.result
    username     = (var.cloud_provider == "aws") ? "ubuntu" : "root"
  })
}

resource "local_file" "inventory" {
  content  = local.inventory
  filename = "${path.module}/inventory"
}

resource "local_file" "vms" {
  content  = jsonencode(local.selected_module.vm_info)
  filename = "${path.module}/vms"
}

/* DNS */

module "godaddy_dns" {
  source = "./modules/dns/godaddy"
  count  = var.dns_provider == "godaddy" ? 1 : 0
  dns    = var.dns
  tld    = var.tld
  ha_ip  = local.selected_module.ha_ip

  providers = {
    godaddy = godaddy.godaddy
  }
}

module "dnsimple_dns" {
  source = "./modules/dns/dnsimple"
  count  = var.dns_provider == "dnsimple" ? 1 : 0
  dns    = var.dns
  tld    = var.tld
  ha_ip  = local.selected_module.ha_ip

  providers = {
    dnsimple = dnsimple.dnsimple
  }
}
