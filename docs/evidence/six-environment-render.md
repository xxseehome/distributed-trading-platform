# Six-environment serial promotion boundary

This evidence records the low-resource execution mode for the six logical
environments. It is a static Kustomize render and image-metadata check; it did
not apply manifests, start additional workloads, or create cloud resources.

## Fixed release metadata

```text
commit_sha:     e2a4a42
api_digest:     sha256:6912690ba7fb5e39ca380b9a12fcffa6ac6ca05666b99c507030934d7d1cf15d
frontend_digest: sha256:71e7ab285cb7a37e8472873102214c43ee756c438feefded9e6eaa50958c656d
```

The same commit and both image digests were substituted into every rendered
overlay. All six checks passed in the required promotion order:

| Order | Environment | API | Frontend | Worker | Runtime decision |
| ---: | --- | ---: | ---: | ---: | --- |
| 1 | dev | 1 | 1 | 1 | render/check only |
| 2 | test | 1 | 1 | 1 | render/check only |
| 3 | perf | 2 | 2 | 2 | render/check only |
| 4 | staging | 2 | 2 | 2 | render/check only |
| 5 | production | 3 | 3 | 3 | keep active in the local cluster |
| 6 | production-dr | 0 | 0 | 0 | dormant; activate only for a DR drill |

## Capacity boundary

`strategy.max-parallel: 1` preserves promotion order, but serial jobs alone do
not make all six full workloads fit in memory. The local Docker Kubernetes VM
has about 7.65 GiB memory; the measured current requests are about 7.39 GiB,
while a full six-environment runtime estimate is about 11.58 GiB. Therefore
this evidence deliberately uses render-only verification for the non-production
and DR targets, keeps Production active, and leaves DR at zero replicas. A
realistic runtime drill must explicitly suspend the previous environment before
starting the next one.

## Reproduction boundary

The check used `kubectl kustomize` for each overlay and substituted the fixed
release metadata before validating the replica counts. No `kubectl apply`, image
pull, rollout, or cloud/API operation was performed by this check. The existing
GitHub promotion workflow remains the controlled path for a future self-hosted
runner execution.
