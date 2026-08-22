terraform {
  required_version = ">= 1.7.0"
  backend "oss" {}
  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.245"
    }
  }
}

provider "alicloud" {
  region = var.region_id
}

variable "enable_apply" {
  type    = bool
  default = false
}

variable "region_id" {
  type    = string
  default = "cn-beijing"
}

variable "image_id" {
  type = string
}

variable "zone_ids" {
  type = list(string)
}

module "dr" {
  source       = "../../modules/k3s-cluster"
  enable_apply = var.enable_apply
  project_name = "distributed-dr"
  region_id    = var.region_id
  image_id     = var.image_id
  zone_ids     = var.zone_ids
  server_count = 1
  system_disk_size = 40
  tags = {
    Project   = "distributed-system"
    Owner     = "xxseehome"
    ManagedBy = "terraform"
    ExpiresAt = "demo-window"
    Cluster   = "dr"
  }
}
