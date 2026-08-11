#!/bin/sh
set -eu
umask 077

# shellcheck source=scripts/s3cli/common.sh
. /scripts/s3cli/common.sh

name=${1:-}
destination=${2:-}
bucket=${3:-${POSTGRES_BACKUP_BUCKET:-postgres-backups}}
case "$name" in *[!A-Za-z0-9_.-]*|'') echo "Unsafe backup object name" >&2; exit 2 ;; esac
case "$name" in *.dump|*.sql.gz) ;; *) echo "Unsupported backup object suffix" >&2; exit 2 ;; esac
case "$destination" in /backups/postgres/downloads/.stage.*) ;; *) echo "Unsafe download staging path" >&2; exit 2 ;; esac
case "$bucket" in *[!a-z0-9.-]*|[-.]*|*[-.]|*..*) echo "Invalid S3 bucket name" >&2; exit 2 ;; esac
if [ ! -d "$destination" ] || [ -L "$destination" ]; then
  echo "Download staging directory is missing or unsafe" >&2
  exit 2
fi
[ -z "$(ls -A "$destination")" ] || { echo "Download staging directory must be empty" >&2; exit 2; }
chmod 0700 "$destination"

head_object "$bucket" "$name" >/dev/null
head_object "$bucket" "$name.sha256" >/dev/null
get_object "$bucket" "$name.sha256" "$destination/$name.sha256" >/dev/null
get_object "$bucket" "$name" "$destination/$name" >/dev/null
chmod 0600 "$destination/$name" "$destination/$name.sha256"

read -r expected listed extra < "$destination/$name.sha256"
if [ "$listed" != "$name" ] || [ -n "${extra:-}" ]; then
  echo "Unsafe downloaded checksum entry" >&2
  exit 1
fi
actual=$(sha256sum "$destination/$name" | cut -d ' ' -f 1)
[ "$actual" = "$expected" ] || { echo "Downloaded checksum mismatch for $name" >&2; exit 1; }
echo "Downloaded and verified s3://$bucket/$name"
