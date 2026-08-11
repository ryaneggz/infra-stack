#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/postgres/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

NAME=${1:-${INFRA_ARG_NAME:-}}
valid_backup_name "$NAME" || {
  printf 'Usage: %s GENERATED_BACKUP_NAME\n' "$0" >&2
  exit 2
}
stage=$(mktemp -d "$DOWNLOAD_DIR/.stage.XXXXXX")
chmod 0700 "$stage"
cleanup=1
cleanup_download() {
  if ((cleanup)); then
    rm -rf -- "$stage"
  fi
}
trap cleanup_download EXIT

s3cli_run /scripts/s3cli/download-backup.sh "$NAME" \
  "/backups/postgres/downloads/$(basename "$stage")" "$POSTGRES_BACKUP_BUCKET" >&2
verify_artifact_checksum "$stage/$NAME"
chmod 0600 "$stage/$NAME" "$stage/$NAME.sha256"
cleanup=0
printf '%s\n' "$stage/$NAME"
