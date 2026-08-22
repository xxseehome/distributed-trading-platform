package kubernetes

import rego.v1

workload_kind := {"Deployment", "StatefulSet", "Job"}

deny contains msg if {
  workload_kind[input.kind]
  some container
  input.spec.template.spec.containers[container].securityContext.privileged == true
  msg := "privileged containers are forbidden"
}

deny contains msg if {
  workload_kind[input.kind]
  some container
  endswith(input.spec.template.spec.containers[container].image, ":latest")
  msg := "latest image tags are forbidden"
}

deny contains msg if {
  workload_kind[input.kind]
  some container
  not input.spec.template.spec.containers[container].resources.limits
  msg := "every workload container must define resource limits"
}

deny contains msg if {
  workload_kind[input.kind]
  some volume
  input.spec.template.spec.volumes[volume].hostPath
  msg := "hostPath volumes are forbidden"
}

deny contains msg if {
  workload_kind[input.kind]
  some container
  input.spec.template.spec.containers[container].securityContext.allowPrivilegeEscalation != false
  msg := "allowPrivilegeEscalation must be false"
}

deny contains msg if {
  workload_kind[input.kind]
  some container
  not container_runs_non_root(container)
  msg := "every workload container must run as non-root"
}

container_runs_non_root(container) if {
  input.spec.template.spec.securityContext.runAsNonRoot == true
}

container_runs_non_root(container) if {
  input.spec.template.spec.containers[container].securityContext.runAsNonRoot == true
}

deny contains msg if {
  input.kind == "Deployment"
  input.metadata.namespace == "production"
  input.spec.replicas < 3
  msg := "production deployments require at least three replicas"
}

deny contains msg if {
  input.kind == "StatefulSet"
  input.metadata.namespace == "production"
  input.metadata.name == "kafka"
  input.spec.replicas < 3
  msg := "production Kafka requires three brokers"
}

deny contains msg if {
  input.kind == "StatefulSet"
  input.metadata.namespace == "production"
  input.metadata.name == "redis"
  input.spec.replicas < 3
  msg := "production Redis requires three instances"
}
