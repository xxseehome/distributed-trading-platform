output "vpc_id" {
  value = try(alicloud_vpc.this[0].id, null)
}

output "vswitch_ids" {
  value = [for item in alicloud_vswitch.this : item.id]
}

output "instance_ids" {
  value = [for item in alicloud_instance.server : item.id]
}

