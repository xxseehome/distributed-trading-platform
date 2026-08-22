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

variable "region_id" {
  type    = string
  default = "cn-hangzhou"
}

variable "enable_apply" {
  type    = bool
  default = false
}

# The OIDC provider and RAM role definitions are deliberately kept in a separate
# state. The approved workflow supplies the exact GitHub repository and subject
# claims; no long-lived AccessKey is stored in this repository.
resource "terraform_data" "oidc_contract" {
  input = {
    provider = "github-actions-trading"
    plan_role = "github-trading-plan"
    apply_role = "github-trading-apply"
    ops_role = "github-trading-ops"
    enabled = var.enable_apply
  }
}

output "oidc_contract" {
  value = terraform_data.oidc_contract.output
}
