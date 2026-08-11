#!/bin/sh
set -eu
umask 077

artifact=${1:-}
bucket=${2:-${POSTGRES_BACKUP_BUCKET:-postgres-backups}}
attempt=${3:-}
delay=${MINIO_UPLOAD_PRE_PUT_DELAY:-0}
checksum="$artifact.sha256"
case "$bucket" in
  *[!a-z0-9.-]*|[-.]*|*[-.]|*..*) echo "Invalid S3 bucket name" >&2; exit 2 ;;
esac
if [ "${#bucket}" -lt 3 ] || [ "${#bucket}" -gt 63 ]; then
  echo "S3 bucket name must be 3-63 characters" >&2
  exit 2
fi
case "$attempt" in *[!a-f0-9]*|'') echo "Invalid upload attempt id" >&2; exit 2 ;; esac
[ "${#attempt}" -eq 32 ] || { echo "Upload attempt id must be 32 hex characters" >&2; exit 2; }
case "$delay" in *[!0-9]*|'') echo "Invalid pre-PUT delay" >&2; exit 2 ;; esac
[ "$delay" -le 5 ] || { echo "Pre-PUT delay must be at most 5 seconds" >&2; exit 2; }
case "$artifact" in
  /backups/postgres/*.dump|/backups/postgres/*.sql.gz) ;;
  *) echo "Refusing artifact outside /backups/postgres" >&2; exit 2 ;;
esac
if [ ! -s "$artifact" ] || [ ! -s "$checksum" ]; then
  echo "Artifact and checksum must both exist and be non-empty" >&2
  exit 1
fi
name=$(basename "$artifact")
case "$name" in *[!A-Za-z0-9_.-]*|'') echo "Unsafe backup object name" >&2; exit 2 ;; esac
case "$name" in
  *_"$attempt".dump|*_"$attempt".sql.gz) ;;
  *) echo "Object name is not bound to its upload attempt id" >&2; exit 2 ;;
esac

mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
mc mb --ignore-existing "local/$bucket" >/dev/null
for key in "$name" "$name.sha256"; do
  if mc stat "local/$bucket/$key" >/dev/null 2>&1; then
    echo "Refusing to overwrite pre-existing remote object: $key" >&2
    exit 3
  fi
done

checksum_created=0
artifact_created=0
owns_object() {
  stat_output=$(mc stat "local/$bucket/$1" 2>/dev/null) || return 1
  case "$stat_output" in
    *X-Amz-Meta-Upload-Attempt*"$attempt"*) return 0 ;;
    *) return 1 ;;
  esac
}
cleanup() {
  if [ "$artifact_created" -eq 1 ] && owns_object "$name"; then
    mc rm --force "local/$bucket/$name" >/dev/null
  fi
  if [ "$checksum_created" -eq 1 ] && owns_object "$name.sha256"; then
    mc rm --force "local/$bucket/$name.sha256" >/dev/null
  fi
}
trap cleanup HUP INT TERM EXIT

# The test-only delay forces concurrent writers past the advisory preflight check.
[ "$delay" -eq 0 ] || sleep "$delay"

# Pinned mc forwards If-None-Match:* to S3 PUT. MinIO atomically returns 412 if
# the key exists, so even writers racing after the stat checks cannot clobber it.
mc put --disable-multipart -H 'If-None-Match:*' \
  -H "X-Amz-Meta-Upload-Attempt:$attempt" \
  "$checksum" "local/$bucket/$name.sha256" >/dev/null
checksum_created=1
owns_object "$name.sha256" || { echo "Could not prove checksum object ownership" >&2; exit 1; }
mc put --disable-multipart -H 'If-None-Match:*' \
  -H "X-Amz-Meta-Upload-Attempt:$attempt" \
  "$artifact" "local/$bucket/$name" >/dev/null
artifact_created=1
owns_object "$name" || { echo "Could not prove artifact object ownership" >&2; exit 1; }

expected=$(cut -d ' ' -f 1 "$checksum")
remote_expected=$(mc cat "local/$bucket/$name.sha256" | cut -d ' ' -f 1)
actual=$(mc cat "local/$bucket/$name" | sha256sum | cut -d ' ' -f 1)
if [ "$expected" != "$remote_expected" ] || [ "$expected" != "$actual" ]; then
  echo "Remote object/checksum mismatch for $name" >&2
  exit 1
fi
trap - HUP INT TERM EXIT
echo "Uploaded and remotely verified s3://$bucket/$name"
