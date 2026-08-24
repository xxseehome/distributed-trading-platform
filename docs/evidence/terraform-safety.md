# Terraform safety boundary

Verified on 2026-08-24 without cloud credentials.

- module and environment `enable_apply` variables default to `false`;
- the Terraform plan workflow passes `-var='enable_apply=false'` for all
  foundation, primary and DR states;
- the local execution used no Terraform provider credentials and did not call
  `terraform apply` or `terraform destroy`;
- the approved apply workflow remains a separate, manual
  `terraform-apply` Environment job that consumes a reviewed plan artifact.

This is a repository-side safety check. It is not evidence that a remote cloud
apply or destroy was performed.
