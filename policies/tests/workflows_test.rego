package workflows

import rego.v1

test_cloud_access_job_is_allowed if {
  result := deny with input as {
    "permissions": {"contents": "read"},
    "jobs": {
      "plan": {
        "permissions": {"contents": "read", "id-token": "write"},
        "steps": [{"uses": "aliyun/configure-aliyun-credentials-action@v1"}]
      }
    }
  }
  count(result) == 0
}

test_workflow_scope_is_rejected if {
  result := deny with input as {
    "permissions": {"contents": "read", "id-token": "write"},
    "jobs": {}
  }
  count(result) > 0
}

test_unrelated_job_is_rejected if {
  result := deny with input as {
    "permissions": {"contents": "read"},
    "jobs": {
      "deploy": {
        "permissions": {"contents": "read", "id-token": "write"},
        "steps": [{"uses": "actions/checkout@v4"}]
      }
    }
  }
  count(result) > 0
}

test_kubernetes_apply_requires_environment if {
  result := deny with input as {
    "permissions": {"contents": "read"},
    "jobs": {
      "deploy": {
        "steps": [{"run": "kubectl apply -f rendered.yaml"}]
      }
    }
  }
  count(result) > 0
}

test_kubernetes_apply_with_environment_is_allowed if {
  result := deny with input as {
    "permissions": {"contents": "read"},
    "jobs": {
      "deploy": {
        "environment": "staging",
        "steps": [{"run": "kubectl apply -f rendered.yaml"}]
      }
    }
  }
  count(result) == 0
}

test_terraform_apply_requires_protected_environment if {
  result := deny with input as {
    "permissions": {"contents": "read"},
    "jobs": {
      "apply": {
        "environment": "staging",
        "steps": [{"run": "terraform apply tfplan"}]
      }
    }
  }
  count(result) > 0
}
