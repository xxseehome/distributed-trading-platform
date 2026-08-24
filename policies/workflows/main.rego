package workflows

import rego.v1

# GitHub OIDC is a narrowly scoped cloud-access capability. A workflow may
# request it only on a job that actually exchanges the token for Alibaba STS.
deny contains msg if {
  input.permissions["id-token"] == "write"
  msg := "workflow-level id-token: write is not allowed; scope it to the cloud access job"
}

deny contains msg if {
  some name
  job := input.jobs[name]
  job.permissions["id-token"] == "write"
  not exchanges_alibaba_oidc(job)
  not exchanges_sigstore_oidc(job)
  msg := sprintf("job %q requests id-token: write without an approved OIDC exchange", [name])
}

exchanges_alibaba_oidc(job) if {
  some index
  step := job.steps[index]
  contains(step.uses, "aliyun/configure-aliyun-credentials-action")
}

# Sigstore keyless signing also uses GitHub OIDC, but it is limited to the
# immutable release job that installs Cosign and signs the exact digest.
exchanges_sigstore_oidc(job) if {
  some index
  step := job.steps[index]
  contains(step.run, "cosign sign")
  some installer_index
  installer := job.steps[installer_index]
  contains(installer.uses, "sigstore/cosign-installer")
}

# Any workflow that applies Kubernetes resources must cross an explicit
# GitHub Environment boundary so a manual dispatch cannot bypass approvals.
deny contains msg if {
  some name
  job := input.jobs[name]
  job_runs_kubectl_apply(job)
  not job.environment
  msg := sprintf("job %q applies Kubernetes resources without an environment", [name])
}

job_runs_kubectl_apply(job) if {
  some index
  step := job.steps[index]
  contains(step.run, "kubectl apply")
}

# Terraform apply is the only workflow allowed to mutate Terraform state, and
# it must use the protected terraform-apply Environment.
deny contains msg if {
  some name
  job := input.jobs[name]
  job_runs_terraform_apply(job)
  job.environment != "terraform-apply"
  msg := sprintf("job %q runs terraform apply without terraform-apply environment", [name])
}

job_runs_terraform_apply(job) if {
  some index
  step := job.steps[index]
  contains(step.run, "terraform apply")
}
