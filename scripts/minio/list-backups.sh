#!/bin/sh
set -eu

bucket=${1:-${POSTGRES_BACKUP_BUCKET:-postgres-backups}}
case "$bucket" in *[!a-z0-9.-]*|[-.]*|*[-.]|*..*) echo "Invalid S3 bucket name" >&2; exit 2 ;; esac
mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
mc ls "local/$bucket/"
