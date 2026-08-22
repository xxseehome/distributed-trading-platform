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

The backend example uses OSS for state and Tablestore for locking. No cloud
credentials are stored in this repository; GitHub Actions obtains short-lived RAM
credentials through OIDC.

