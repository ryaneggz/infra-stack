#!/bin/sh
set -eu

# shellcheck source=scripts/s3cli/common.sh
. /scripts/s3cli/common.sh

bucket=${1:-${POSTGRES_BACKUP_BUCKET:-postgres-backups}}
case "$bucket" in *[!a-z0-9.-]*|[-.]*|*[-.]|*..*) echo "Invalid S3 bucket name" >&2; exit 2 ;; esac
s3api list-objects-v2 --bucket "$bucket" \
  --query 'Contents[].{Key:Key,Size:Size,LastModified:LastModified}' --output table
