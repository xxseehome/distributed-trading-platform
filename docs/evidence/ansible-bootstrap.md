# Ansible bootstrap evidence

The pinned local bootstrap was run twice on 2026-08-23 with Ansible Core
2.19.1:

```text
first run:  ok=7 changed=1 failed=0
second run: ok=7 changed=0 failed=0
```

The second run made no changes. Docker Desktop and the required host
architecture assertions passed.
