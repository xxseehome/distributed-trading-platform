# Local security controls

Verified on 2026-08-24:

- Gatekeeper audit: `1/1` Ready;
- Gatekeeper controller-manager: `3/3` Ready;
- the `K8sRequiredResources` constraint is installed;
- Falco rules ConfigMap is installed.

A server-side dry-run Pod with `busybox:latest`, privileged mode, and no
resource requests was rejected by the `trading-pod-baseline` admission
webhook; no test object was created.

The local Docker Desktop environment is not used as evidence of host-level
Falco eBPF detection. CI remains the authoritative execution path for
Gitleaks, Trivy, Syft and OPA/Conftest gates.

Secret-boundary check:

- `git ls-files .runtime` returned zero files;
- no tracked kubeconfig, private key, PEM or secret-named file was found;
- PostgreSQL credentials are referenced by Kubernetes Secret objects only;
- the DR drill copies the Secret through the Kubernetes API and never prints
  or writes its value to an artifact.

The plaintext `trading` password in the CI PostgreSQL service is a disposable
test fixture, not a production or cloud credential.
