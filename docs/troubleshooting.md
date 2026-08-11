# Troubleshooting

- **Missing `.env`**: run `make init`. It will not overwrite an existing file.
- **External network missing**: run `make network` or `make up`, not raw Compose startup.
- **Port already allocated**: change the corresponding `*_PORT` in `.env`; for workstation tunnels use `LOCAL_PORT_OFFSET`.
- **`postgres` name conflict**: only one stack is supported per Docker host. Identify the owner before removing or renaming another container.
- **PostgreSQL unhealthy**: run `docker compose --env-file .env -f compose.yml logs postgres`. Extension initialization runs only for a new volume; on an existing volume create `vectorscale CASCADE` as an owner and verify both `vector` and `vectorscale`.
- **MinIO/backup preflight failure**: never bypass preflight. Remove symlinks, restore ownership to the invoking UID, and allow scripts to enforce mode `0700`.
- **S3 `PreconditionFailed`**: the remote artifact or checksum key already exists or won a race. The no-clobber guard worked. Do not delete unknown keys; inspect metadata and choose a new generated backup.
- **AWS CLI cannot connect**: ensure MinIO is healthy, the `infra` network exists, and `AWS_CLI_IMAGE=amazon/aws-cli:2.36.20` remains in `.env`. Run `make up`, then retry.
- **Image tag/platform failure**: run `python3 scripts/validate-image-tags.py`. Select a fixed upstream tag that publishes Linux `amd64` and `arm64`; never switch to `latest` or remove version specificity.
- **Slow first start/CI**: the Timescale all-extensions image is large. Later pulls can use Docker layer cache.
- **Interrupted backup**: run `make verify-backups`. Local files remain for inspection; remote cleanup removes only attempt-owned objects.
- **Restore rejected**: use the path printed by `make download-backup`. Restore scripts reject local source dumps, symlinks, malformed names, missing sidecars, and checksum mismatches.
- **Cluster target readiness timeout**: inspect `docker logs <container>` and confirm the disposable target is running PostgreSQL 17. `restore-all` waits 180 seconds by default; use process-only `INFRA_RESTORE_READY_TIMEOUT=300` (allowed range 1–600) only when healthy initialization is known to need longer.
- **Cleanup failure in CI**: inspect reported container/volume/network/path IDs. `scripts/ci-cleanup.sh` intentionally turns leftovers into a failed job.

For normal recovery order, see [operations](operations.md#failure-recovery); for data recovery, see [backups and restore](backups-and-restore.md).
