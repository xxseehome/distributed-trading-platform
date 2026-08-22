package ci

required_jobs := {"quality", "integration", "gitleaks", "trivy", "syft", "opa", "build"}

deny[msg] {
  missing := required_jobs - {name | input.jobs[name]}
  count(missing) > 0
  msg := sprintf("CI is missing required jobs: %v", [missing])
}

deny[msg] {
  not input.jobs.build.needs[_] == "quality"
  msg := "build must depend on the quality gate"
}

deny[msg] {
  not input.jobs.build.needs[_] == "integration"
  msg := "build must depend on the integration gate"
}

deny[msg] {
  not input.jobs.build.needs[_] == "gitleaks"
  msg := "build must depend on the Gitleaks gate"
}

deny[msg] {
  not input.jobs.build.needs[_] == "trivy"
  msg := "build must depend on the Trivy gate"
}

deny[msg] {
  not input.jobs.build.needs[_] == "syft"
  msg := "build must depend on the Syft gate"
}

deny[msg] {
  not input.jobs.build.needs[_] == "opa"
  msg := "build must depend on the OPA gate"
}
