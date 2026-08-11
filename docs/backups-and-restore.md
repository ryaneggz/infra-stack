# PostgreSQL backups and restore

## Create and verify

```bash
INFRA_ARG_DB=app make backup-db
make backup-all
make verify-backups
make list-backups
```

`backup-db` writes a custom-format `..._app_<128-bit-id>.dump` plus `.sha256`. `backup-all` writes a gzip SQL `..._cluster_<128-bit-id>.sql.gz` plus `.sha256`.

Publication takes a non-blocking host `flock`, stages files under mode-`0700` directories, sets files to `0600`, and rejects local collisions. The official AWS CLI 2.36.20 uses S3 API `put-object` with `If-None-Match: *`; this is one atomic non-multipart PUT (maximum 5 GiB). The checksum is published before the artifact. MinIO returns HTTP 412 if either key already exists or races into existence. Attempt metadata and guarded cleanup delete only keys proven to belong to the failed attempt.

CI proves bucket creation, head/get/list APIs, metadata inspection, checksum-key races, a separate artifact-key race after checksum creation, winner preservation, and ownership-safe loser cleanup.

## Download before restore

Never restore the local source artifact as proof of remote recoverability. Download both remote objects into a fresh mode-`0700` stage, verify the sidecar filename and SHA-256, and retain both files as `0600`:

```bash
INFRA_ARG_NAME=20260810T120000Z_app_0123456789abcdef0123456789abcdef.dump \
  make download-backup
```

The command prints the verified staged path. Preserve that output for restore.

## Restore one database

```bash
INFRA_ARG_FILE=backups/postgres/downloads/.stage.ABCDEF/20260810T120000Z_app_0123456789abcdef0123456789abcdef.dump \
INFRA_ARG_TARGET=restore_app_test \
  make restore-db

docker compose --env-file .env -f compose.yml exec postgres \
  psql -U infra -d restore_app_test
```

`restore-db.sh` independently validates the adjacent sidecar before dropping/creating the target database.

## Restore a cluster dump

`pg_dumpall` contains roles and password hashes. Treat the gzip and checksum as sensitive: mode `0600`, restricted operator access, encrypted storage/transport, no commits, chat uploads, or casual copies.

Restore into a fresh PostgreSQL 17 container using the same Timescale all-extensions image. Start it and invoke restore immediately; `restore-all` waits for three consecutive readiness checks (up to 180 seconds by default), then verifies PostgreSQL 17 before consuming the dump:

```bash
docker run -d --name pg17-restore --network infra \
  -e POSTGRES_PASSWORD=temporary timescale/timescaledb-ha:pg17.6-ts2.21.3-all

INFRA_ARG_FILE=backups/postgres/downloads/.stage.ABCDEF/20260810T120000Z_cluster_0123456789abcdef0123456789abcdef.sql.gz \
INFRA_ARG_CONTAINER=pg17-restore \
  make restore-all

docker rm -fv pg17-restore
```

Verify application data and roles before deleting the disposable target. For unusually slow hosts, set a bounded process-environment override from 1–600 seconds, for example `INFRA_RESTORE_READY_TIMEOUT=300` before `make restore-all`. A timeout exits nonzero with the target name and elapsed limit; it never starts the restore.

## Argument safety and limitations

Operator values travel only through inherited `INFRA_ARG_*` environment variables. Make rejects legacy `DB=`, `NAME=`, `FILE=`, `TARGET=`, `CONTAINER=`, and `CONFIRM=` assignments before payload expansion. `make security-test` exercises quotes, separators, substitutions, whitespace, and traversal.

Backups are manual and local-first. No scheduling, retention, TLS, encryption, object lock, or off-host replication is included. The S3 single-PUT limit is 5 GiB. See the [roadmap](minio-replication-roadmap.md).
