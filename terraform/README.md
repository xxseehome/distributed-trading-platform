# Terraform layout

The three state boundaries are intentional:

```text
terraform/environments/foundation
terraform/environments/primary
terraform/environments/dr
```

Each environment uses the shared `modules/k3s-cluster` module. The module defaults
to `enable_apply = false`; Phase 0 must confirm trial quota, inventory, zones and
the 4/8-hour cost gate before an approved workflow enables it.

The backend uses the existing private OSS bucket for encrypted state. GitHub
Actions serializes Terraform plan, apply, and adoption workflows with a shared
concurrency group; no additional Tablestore lock resource is created. This
keeps the demo within the existing trial resources, but it does not protect a
Terraform command launched outside GitHub Actions, so local and ad-hoc runs
must remain serialized. No cloud credentials are stored in this repository;
GitHub Actions obtains short-lived RAM credentials through OIDC.
