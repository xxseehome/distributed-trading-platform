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
  msg := sprintf("job %q requests id-token: write without Alibaba OIDC exchange", [name])
}

exchanges_alibaba_oidc(job) if {
  some index
  step := job.steps[index]
  contains(step.uses, "aliyun/configure-aliyun-credentials-action")
}
