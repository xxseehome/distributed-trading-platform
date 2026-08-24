# Local entrypoint evidence

The active low-resource profile exposes one Traefik HTTP entrypoint:

```text
URL:  http://127.0.0.1:8080
Host: bookstore.example.invalid
```

The Kubernetes Ingress keeps the explicit `bookstore.example.invalid` route
and now also has a local-only hostless fallback. Therefore a browser opening
`http://127.0.0.1:8080/` is accepted without a manually supplied Host header.
The resilience workflow and local scripts still use the explicit hostname by
default.
Separate per-environment, Grafana, and Argo CD hostnames remain future
extensions and are not claimed as deployed.
