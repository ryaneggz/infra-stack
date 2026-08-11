#!/bin/sh
set -eu
umask 077

# shellcheck source=scripts/s3cli/common.sh
. /scripts/s3cli/common.sh

artifact=${1:-}
bucket=${2:-${POSTGRES_BACKUP_BUCKET:-postgres-backups}}
attempt=${3:-}
delay=${S3_UPLOAD_PRE_PUT_DELAY:-0}
test_ready_file=${S3_UPLOAD_TEST_READY_FILE:-}
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
case "$test_ready_file" in
  ''|/backups/postgres/.artifact-put-race-ready) ;;
  *) echo "Invalid test barrier path" >&2; exit 2 ;;
esac
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

create_bucket_if_missing "$bucket"
for key in "$name" "$name.sha256"; do
  if head_object "$bucket" "$key" >/dev/null 2>&1; then
    echo "Refusing to overwrite pre-existing remote object: $key" >&2
    exit 3
  fi
done

checksum_created=0
artifact_created=0
owns_object() {
  owner=$(head_object "$bucket" "$1" --query 'Metadata."upload-attempt"' --output text 2>/dev/null) || return 1
  [ "$owner" = "$attempt" ]
}
cleanup() {
  if [ "$artifact_created" -eq 1 ] && owns_object "$name"; then
    s3api delete-object --bucket "$bucket" --key "$name" >/dev/null
  fi
  if [ "$checksum_created" -eq 1 ] && owns_object "$name.sha256"; then
    s3api delete-object --bucket "$bucket" --key "$name.sha256" >/dev/null
  fi
}
trap cleanup HUP INT TERM EXIT

# Test-only barrier; inert unless the smoke test explicitly enables it.
if [ -n "$test_ready_file" ]; then
  : > "$test_ready_file"
  chmod 0600 "$test_ready_file"
fi
[ "$delay" -eq 0 ] || sleep "$delay"

# s3api put-object is a single atomic PUT. The pinned AWS CLI sends the modeled
# If-None-Match header, and MinIO returns HTTP 412 when another writer owns key.
s3api put-object --bucket "$bucket" --key "$name.sha256" --body "$checksum" \
  --if-none-match '*' --metadata "upload-attempt=$attempt" >/dev/null
checksum_created=1
owns_object "$name.sha256" || { echo "Could not prove checksum object ownership" >&2; exit 1; }
s3api put-object --bucket "$bucket" --key "$name" --body "$artifact" \
  --if-none-match '*' --metadata "upload-attempt=$attempt" >/dev/null
artifact_created=1
owns_object "$name" || { echo "Could not prove artifact object ownership" >&2; exit 1; }

verify_dir=$(mktemp -d /tmp/s3cli-upload.XXXXXX)
trap 'rm -rf "$verify_dir"; cleanup' HUP INT TERM EXIT
get_object "$bucket" "$name.sha256" "$verify_dir/$name.sha256" >/dev/null
get_object "$bucket" "$name" "$verify_dir/$name" >/dev/null
expected=$(cut -d ' ' -f 1 "$checksum")
remote_expected=$(cut -d ' ' -f 1 "$verify_dir/$name.sha256")
actual=$(sha256sum "$verify_dir/$name" | cut -d ' ' -f 1)
if [ "$expected" != "$remote_expected" ] || [ "$expected" != "$actual" ]; then
  echo "Remote object/checksum mismatch for $name" >&2
  exit 1
fi
rm -rf "$verify_dir"
trap - HUP INT TERM EXIT
echo "Uploaded and remotely verified s3://$bucket/$name"
