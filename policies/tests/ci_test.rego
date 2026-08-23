package ci

import rego.v1

test_security_gates_are_required if {
  result := deny with input as {
    "jobs": {
      "quality": {},
      "integration": {},
      "gitleaks": {},
      "trivy": {},
      "trivy-config": {},
      "syft": {},
      "opa": {},
      "terraform": {},
      "build": {
        "needs": ["quality", "integration", "gitleaks", "trivy", "trivy-config", "syft", "opa", "terraform"]
      }
    }
  }
  count(result) == 0
}

test_missing_trivy_config_is_rejected if {
  result := deny with input as {
    "jobs": {
      "quality": {},
      "integration": {},
      "gitleaks": {},
      "trivy": {},
      "syft": {},
      "opa": {},
      "terraform": {},
      "build": {
        "needs": ["quality", "integration", "gitleaks", "trivy", "syft", "opa", "terraform"]
      }
    }
  }
  count(result) > 0
}
