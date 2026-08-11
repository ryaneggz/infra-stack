# Operations

## Install and initialize

Prerequisites: Linux Docker Engine, Docker Compose v2/v5, GNU Make, Bash, OpenSSL, `flock`, Python 3, and disk capacity for images plus data.

```bash
git clone https://github.com/ryaneggz/infra-stack.git
cd infra-stack
make init
make config
make up
```

`make preflight` is automatic for startup and backup targets. It rejects symlinked/wrong-owner host paths, enforces mode `0700`, and prepares bind sources before Compose's fail-closed `create_host_path: false` mounts.

## Routine lifecycle

```bash
make pull       # pull core and AWS CLI utility images
make up         # four core services; wait for health
make ps
make logs
make down       # preserve volumes, MinIO data, and backups
```

Use `make network` when validating raw Compose manually; normal startup creates the external network automatically. Optional UIs use `make clients` or `make clients-pgadmin`.

## Reset

This destroys named volumes, MinIO host data, and local backups:

```bash
INFRA_CONFIRM_RESET=destroy make reset
```

The legacy `CONFIRM=destroy` Make assignment is rejected. Confirm backups are restored/tested elsewhere before reset.

## Failure recovery

1. Run `make ps` and inspect `make logs`.
2. Correct `.env`, port, ownership, capacity, or image issues; do not bypass preflight.
3. Re-run `make config` and `make up`. Existing volumes remain.
4. If an interrupted backup left a local pair, run `make verify-backups`. Publication refuses pre-existing remote keys and cleanup deletes only objects whose attempt metadata proves ownership.
5. For data recovery, use only checksum-verified downloaded bytes as described in [backups and restore](backups-and-restore.md).
6. Use reset only when data loss is intentional.

## CI and local verification

GitHub Actions performs:

- repository hygiene, ShellCheck, stale-client/static security assertions;
- documentation link/command lint;
- fixed-tag and Linux `amd64`/`arm64` manifest validation;
- secure mode and Compose base/overlay/profile validation;
- 112 adversarial Make-injection probes and localhost-port assertions;
- image pulls and a full four-service smoke;
- bucket initialization, independent checksum/artifact conditional-write conflicts, metadata ownership, downloads/checksums, both restore formats, and bounded fresh-target readiness/timeout behavior;
- strict cleanup proving zero containers, volumes, network, `.env`, data, or backups remain.

Run the closest local equivalent:

```bash
make init
make config
make security-test
python3 scripts/lint-docs.py
python3 scripts/validate-image-tags.py
make smoke
```

CI always runs `scripts/ci-cleanup.sh`, including after failures.
