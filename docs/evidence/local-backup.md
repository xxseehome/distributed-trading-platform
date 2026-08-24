# Local recovery backup schedule

The repository now contains a low-resource backup workflow:

- `.github/workflows/backup-local.yml` runs every 15 minutes and can also be
  started manually;
- it is restricted to the protected branch and the existing local self-hosted
  runner labels;
- `scripts/local-backup.sh` writes a `0600` PostgreSQL gzip dump and a minimal
  Kafka topic/consumer-offset snapshot;
- the GitHub artifact retention is 7 days;
- the workflow does not include message payloads, cloud credentials or any
  cloud resource operation.

The schedule is dormant while the Mac runner is offline; GitHub queues or
skips the job according to runner availability. A successful run is required
before claiming an artifact-based RPO measurement.

Local smoke run on 2026-08-24 produced and validated:

```text
.runtime/backups/postgres-20260824T003845Z.sql.gz  gzip OK, mode 0600
.runtime/backups/kafka-20260824T003845Z.txt         topic/offset metadata
```
