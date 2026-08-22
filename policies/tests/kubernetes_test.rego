package kubernetes

test_latest_is_rejected if {
  result := deny with input as {
    "kind": "Deployment",
    "spec": {"template": {"spec": {"containers": [{
      "image": "example/app:latest",
      "resources": {"limits": {"cpu": "1"}},
      "securityContext": {"allowPrivilegeEscalation": false, "runAsNonRoot": true}
    }]}}}
  }
  count(result) > 0
}

test_secure_deployment_is_allowed if {
  result := deny with input as {
    "kind": "Deployment",
    "metadata": {"namespace": "dev"},
    "spec": {"replicas": 1, "template": {"spec": {"containers": [{
      "image": "example/app:1.0",
      "resources": {"limits": {"cpu": "1"}},
      "securityContext": {"allowPrivilegeEscalation": false, "runAsNonRoot": true}
    }]}}}
  }
  count(result) == 0
}

test_production_stateful_service_requires_three_replicas if {
  result := deny with input as {
    "kind": "StatefulSet",
    "metadata": {"namespace": "production", "name": "kafka"},
    "spec": {"replicas": 1, "template": {"spec": {"containers": [{
      "image": "example/kafka:1.0",
      "resources": {"limits": {"cpu": "1"}},
      "securityContext": {"allowPrivilegeEscalation": false, "runAsNonRoot": true}
    }]}}}
  }
  count(result) > 0
}

test_host_path_is_rejected if {
  result := deny with input as {
    "kind": "Deployment",
    "spec": {
      "template": {
        "spec": {
          "containers": [{
            "image": "example/app:1.0",
            "resources": {"limits": {"cpu": "1"}},
            "securityContext": {"allowPrivilegeEscalation": false, "runAsNonRoot": true}
          }],
          "volumes": [{"name": "host", "hostPath": {"path": "/var/run"}}]
        }
      }
    }
  }
  count(result) > 0
}
