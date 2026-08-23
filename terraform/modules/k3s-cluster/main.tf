resource "alicloud_vpc" "this" {
  count      = var.enable_apply ? 1 : 0
  vpc_name   = "${var.project_name}-vpc"
  cidr_block = var.vpc_cidr
  tags       = var.tags
}

resource "alicloud_vswitch" "this" {
  count        = var.enable_apply ? length(var.zone_ids) : 0
  vpc_id       = alicloud_vpc.this[0].id
  zone_id      = var.zone_ids[count.index]
  cidr_block   = var.vswitch_cidrs[count.index]
  vswitch_name = "${var.project_name}-vsw-${count.index + 1}"
  tags         = var.tags
}

resource "alicloud_security_group" "this" {
  count               = var.enable_apply ? 1 : 0
  security_group_name = "${var.project_name}-sg"
  description         = "Private cluster security group; public ingress is not allowed."
  vpc_id              = alicloud_vpc.this[0].id
  tags                = var.tags
}

resource "alicloud_security_group_rule" "internal" {
  count             = var.enable_apply ? 1 : 0
  type              = "ingress"
  ip_protocol       = "all"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "-1/-1"
  cidr_ip           = var.vpc_cidr
  security_group_id = alicloud_security_group.this[0].id
}

resource "alicloud_instance" "server" {
  count                      = var.enable_apply ? var.server_count : 0
  image_id                   = var.image_id
  instance_type              = var.instance_type
  instance_name              = "${var.project_name}-k3s-${count.index + 1}"
  vswitch_id                 = alicloud_vswitch.this[count.index].id
  security_groups            = [alicloud_security_group.this[0].id]
  system_disk_category       = "cloud_essd"
  system_disk_size           = var.system_disk_size
  internet_max_bandwidth_out = 0
  internet_charge_type       = "PayByTraffic"
  tags                       = var.tags
}
