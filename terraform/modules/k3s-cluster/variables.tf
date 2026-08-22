variable "enable_apply" {
  type        = bool
  description = "Safety gate; must be enabled only by an approved workflow after the cost check."
  default     = false
}

variable "project_name" {
  type = string
}

variable "region_id" {
  type = string
}

variable "zone_ids" {
  type        = list(string)
  description = "Distinct availability zones for the cluster nodes."
}

variable "vpc_cidr" {
  type    = string
  default = "10.60.0.0/16"
}

variable "vswitch_cidrs" {
  type    = list(string)
  default = ["10.60.1.0/24", "10.60.2.0/24", "10.60.3.0/24"]
}

variable "server_count" {
  type    = number
  default = 1
}

variable "instance_type" {
  type    = string
  default = "ecs.t6-c1m2.large"
}

variable "image_id" {
  type        = string
  description = "Ubuntu 22.04 image id selected during Phase 0."
}

variable "system_disk_size" {
  type    = number
  default = 40
}

variable "tags" {
  type    = map(string)
  default = {}
}

check "zone_count_matches_nodes" {
  assert {
    condition     = var.server_count <= length(var.zone_ids)
    error_message = "server_count cannot exceed the number of supplied availability zones."
  }
}

check "zones_are_distinct" {
  assert {
    condition     = length(distinct(var.zone_ids)) == length(var.zone_ids)
    error_message = "Production K3s servers must use distinct availability zones."
  }
}
