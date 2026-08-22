package ci

import rego.v1

required_jobs := {"quality", "integration", "gitleaks", "trivy", "syft", "opa", "build"}

deny contains msg if {
  missing := required_jobs - {name | input.jobs[name]}
  count(missing) > 0
  msg := sprintf("CI is missing required jobs: %v", [missing])
}

deny contains msg if {
  not has_need("quality")
  msg := "build must depend on the quality gate"
}

deny contains msg if {
  not has_need("integration")
  msg := "build must depend on the integration gate"
}

deny contains msg if {
  not has_need("gitleaks")
  msg := "build must depend on the Gitleaks gate"
}

deny contains msg if {
  not has_need("trivy")
  msg := "build must depend on the Trivy gate"
}

deny contains msg if {
  not has_need("syft")
  msg := "build must depend on the Syft gate"
}

deny contains msg if {
  not has_need("opa")
  msg := "build must depend on the OPA gate"
}

has_need(need) if {
  some index
  input.jobs.build.needs[index] == need
}
