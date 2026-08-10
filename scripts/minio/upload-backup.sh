#!/bin/sh
set -eu

artifact=${1:-}
bucket=${2:-${POSTGRES_BACKUP_BUCKET:-postgres-backups}}
checksum="$artifact.sha256"
case "$bucket" in
  *[!a-z0-9.-]*|[-.]*|*[-.]|*..*) echo "Invalid S3 bucket name" >&2; exit 2 ;;
esac
[ "${#bucket}" -ge 3 ] && [ "${#bucket}" -le 63 ] || {
  echo "S3 bucket name must be 3-63 characters" >&2
  exit 2
}
case "$artifact" in
  /backups/postgres/*.dump|/backups/postgres/*.sql.gz) ;;
  *) echo "Refusing artifact outside /backups/postgres" >&2; exit 2 ;;
esac
if [ ! -s "$artifact" ] || [ ! -s "$checksum" ]; then
  echo "Artifact and checksum must both exist and be non-empty" >&2
  exit 1
fi

name=$(basename "$artifact")
mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
mc mb --ignore-existing "local/$bucket" >/dev/null
cleanup() {
  mc rm --force "local/$bucket/$name" "local/$bucket/$name.sha256" >/dev/null 2>&1 || true
}
trap cleanup HUP INT TERM EXIT

# Checksum first means the data object is never visible without its verifier.
mc cp "$checksum" "local/$bucket/$name.sha256" >/dev/null
mc cp "$artifact" "local/$bucket/$name" >/dev/null
expected=$(cut -d ' ' -f 1 "$checksum")
remote_expected=$(mc cat "local/$bucket/$name.sha256" | cut -d ' ' -f 1)
actual=$(mc cat "local/$bucket/$name" | sha256sum | cut -d ' ' -f 1)
[ "$expected" = "$remote_expected" ] && [ "$expected" = "$actual" ] || {
  echo "Remote object/checksum mismatch for $name" >&2
  exit 1
}
mc stat "local/$bucket/$name" >/dev/null
mc stat "local/$bucket/$name.sha256" >/dev/null
trap - HUP INT TERM EXIT
echo "Uploaded and remotely verified s3://$bucket/$name"
