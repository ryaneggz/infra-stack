#!/bin/sh
set -eu
umask 077

# shellcheck source=scripts/s3cli/common.sh
. /scripts/s3cli/common.sh

name=${1:-}
bucket=${2:-}
token=${3:-}
case "$name" in *[!A-Za-z0-9_.-]*|'') echo "Unsafe test object name" >&2; exit 2 ;; esac
case "$name" in *.dump|*.sql.gz) ;; *) echo "Unsupported test object suffix" >&2; exit 2 ;; esac
case "$bucket" in *[!a-z0-9.-]*|[-.]*|*[-.]|*..*) echo "Invalid S3 bucket name" >&2; exit 2 ;; esac
case "$token" in *[!a-f0-9]*|'') echo "Invalid test owner token" >&2; exit 2 ;; esac
[ "${#token}" -eq 32 ] || { echo "Test owner token must be 32 hex characters" >&2; exit 2; }

source_file=/tmp/external-artifact
printf 'external-conflict-%s' "$token" > "$source_file"
s3api put-object --bucket "$bucket" --key "$name" --body "$source_file" \
  --if-none-match '*' --metadata "test-owner=$token" >/dev/null
echo "Inserted external artifact conflict: $name"
