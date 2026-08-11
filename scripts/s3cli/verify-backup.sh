#!/bin/sh
set -eu
umask 077

# shellcheck source=scripts/s3cli/common.sh
. /scripts/s3cli/common.sh

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

stage=$(mktemp -d /tmp/s3cli-verify.XXXXXX)
trap 'rm -rf "$stage"' HUP INT TERM EXIT
get_object "$bucket" "$name.sha256" "$stage/$name.sha256" >/dev/null
get_object "$bucket" "$name" "$stage/$name" >/dev/null
expected=$(cut -d ' ' -f 1 "$checksum")
remote_expected=$(cut -d ' ' -f 1 "$stage/$name.sha256")
actual=$(sha256sum "$stage/$name" | cut -d ' ' -f 1)
if [ "$expected" != "$remote_expected" ] || [ "$expected" != "$actual" ]; then
  echo "Remote backup pair mismatch: $name" >&2
  exit 1
fi
head_object "$bucket" "$name" >/dev/null
head_object "$bucket" "$name.sha256" >/dev/null
rm -rf "$stage"
trap - HUP INT TERM EXIT
