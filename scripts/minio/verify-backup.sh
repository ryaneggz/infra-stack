#!/bin/sh
set -eu

name=${1:-}
bucket=${2:-${POSTGRES_BACKUP_BUCKET:-postgres-backups}}
case "$name" in *[!A-Za-z0-9_.-]*|'') echo "Unsafe backup object name" >&2; exit 2 ;; esac
case "$name" in *.dump|*.sql.gz) ;; *) echo "Unsupported backup object suffix" >&2; exit 2 ;; esac
case "$bucket" in *[!a-z0-9.-]*|[-.]*|*[-.]|*..*) echo "Invalid S3 bucket name" >&2; exit 2 ;; esac
artifact="/backups/postgres/$name"
checksum="$artifact.sha256"
if [ ! -s "$artifact" ] || [ ! -s "$checksum" ]; then
  echo "Missing local backup pair" >&2
  exit 1
fi

mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
expected=$(cut -d ' ' -f 1 "$checksum")
remote_expected=$(mc cat "local/$bucket/$name.sha256" | cut -d ' ' -f 1)
actual=$(mc cat "local/$bucket/$name" | sha256sum | cut -d ' ' -f 1)
if [ "$expected" != "$remote_expected" ] || [ "$expected" != "$actual" ]; then
  echo "Remote backup pair mismatch: $name" >&2
  exit 1
fi
mc stat "local/$bucket/$name" >/dev/null
mc stat "local/$bucket/$name.sha256" >/dev/null
